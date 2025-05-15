#!/bin/bash
# =========================================================
# 一键申请 / 续期 Let's Encrypt + 自动处理 Nginx
# =========================================================

########## 手动可改区域 ################################
DOMAIN="example.com"                 # 支持 *.example.com，但不推荐，复杂
DOMAINS=(a.example.com b.example.com c.example.net)   # 想放进同一张证书的域名，这种方式就不要再写泛域名了
PRIMARY=${DOMAINS[0]}                                 # 取第 1 个做“主域名”
EMAIL="admin@example.com"    # 随便填就可以
WEBROOT="/var/www/_acme_challenge"
NGINX_CONF_DIR="/etc/nginx/conf.d"
#NGINX_SSL_DIR="/etc/nginx/ssl/${DOMAIN//\*/_}"  # 把 * 替成 _
NGINX_SSL_DIR="/etc/nginx/ssl/${PRIMARY//\*/_}"       # 多个域名的情况

####################### 单域名改多域名还需调整：
# 原来 server_name $DOMAIN;
# 改成 server_name ${DOMAINS[*]};
# 原来 acme.sh --issue -d "$DOMAIN"  ...其它参数...
# 改成
# acme.sh --issue \
#     $(printf -- '-d %s ' "${DOMAINS[@]}") \
#     --webroot "$WEBROOT" \
#     --key-file       "$NGINX_SSL_DIR/key.pem" \
#     --fullchain-file "$NGINX_SSL_DIR/fullchain.pem" \
#     --reloadcmd      "bash -c '$(declare -f reload_nginx); reload_nginx'"
# #######################

# ==== 若想自动申请通配符，需填写 DNS API（示例 Aliyun）=========
export Ali_Key="YOUR_Ali_Key"
export Ali_Secret="YOUR_Ali_Secret"
# 如果手动的话
# acme.sh --issue --dns -d shu.aixinwu.org -d *.shu.aixinwu.org --yes-I-know-dns-manual-mode-enough-go-ahead-please
# 根据上一步返回的 TXT 记录添加要求，在相应的域名 DNS 服务提供商那里添加好对应的 TXT 记录
# 在添加好 TXT 记录之后，就可以使用更新命令来请求颁发泛域名证书。执行下面这条命令之后可以发现返回了生成的文件的本地路径
# acme.sh --renew -d shu.aixinwu.org -d *.shu.aixinwu.org --yes-I-know-dns-manual-mode-enough-go-ahead-please
###########################################################

# 带格式的echo函数
function echo_info() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m$@\033[0m"
}
function echo_warning() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m$@\033[0m"
}
function echo_error() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m$@\033[0m"
}

# ============ 0) 必须是 root ============================
[[ $(id -u) -eq 0 ]] || { echo_error "请使用 root 执行"; exit 99; }

# ============ 1) 发行版检测 + git 安装 ===================
if ! command -v git &>/dev/null; then
    if grep -qi "ubuntu" /etc/os-release; then
        os="ubuntu"; pkg_install() { apt-get update -y; apt-get install -y "$@"; }
    elif [[ -e /etc/centos-release ]]; then
        os="centos"; pkg_install() { yum install -y "$@"; }
    elif [[ -e /etc/rocky-release ]]; then
        os="rocky";  pkg_install() { dnf install -y "$@"; }
    elif [[ -e /etc/almalinux-release ]]; then
        os="alma";   pkg_install() { dnf install -y "$@"; }
    else
        os="unknown"; pkg_install() { echo_error "未知发行版，无法自动安装，请手动安装 git"; exit 98; }
    fi

    echo_warning "git 未安装，自动安装中..."
    pkg_install git
fi
# ========================================================

# ============ 2) 查找正在运行的 nginx ===================
detect_nginx_bin() {
    local pid exe
    pid=$(pgrep -o -x nginx || true)
    if [[ $pid && -e /proc/$pid/exe ]]; then
        exe=$(readlink -f /proc/$pid/exe)
        [[ -x $exe ]] && { echo "$exe"; return; }
    fi
    exe=$(command -v nginx 2>/dev/null || true)
    [[ -x $exe ]] && { echo "$exe"; return; }
    for p in /usr/local/nginx/sbin/nginx /usr/sbin/nginx; do
        [[ -x $p ]] && { echo "$p"; return; }
    done
    echo_error "未找到正在运行的 nginx 可执行文件"
    exit 1
}
NGINX_BIN=$(detect_nginx_bin)
echo_info "nginx -> $NGINX_BIN"

reload_nginx() {
    if "$NGINX_BIN" -t >/dev/null 2>&1 && "$NGINX_BIN" -s reload; then
        echo_info "nginx 重载完成 (-s reload)"
    elif command -v systemctl &>/dev/null && systemctl is-active nginx &>/dev/null; then
        systemctl reload nginx
        echo_info "nginx 重载完成 (systemctl)"
    else
        echo_error "无法 reload nginx，请手动检查"
        exit 1
    fi
}
# ========================================================

# ============ 3) 安装 acme.sh ===========================
### <<< 删除 curl/sed/grep 依赖显式检测 >>> ###

if ! command -v acme.sh &>/dev/null; then
    echo_info "安装 acme.sh ..."
    #git clone --depth=1 https://gitee.com/neilpang/acme.sh.git
    git clone --depth=1 https://gitee.com/neilpang/acme.sh.git ~/acme.sh
    ~/acme.sh/acme.sh --install -m "$EMAIL"
    # 软链接，方便脚本使用
    ln -sf ~/.acme.sh/acme.sh /usr/local/bin/acme.sh
else
    echo_info "✓ acme.sh 已存在，跳过安装"
    echo_info "如需升级，请使用下面的命令："
    echo "acme.sh --upgrade --auto-upgrade"
    echo
fi
# ========================================================

# ============ 4) 生成 / 修改 Nginx 配置 =================
ACME_TEMP_CONF="${NGINX_CONF_DIR}/__acme_${PRIMARY//\*/_}.conf"      ### >>> MULTI <<<
FINAL_CONF="${NGINX_CONF_DIR}/${PRIMARY//\*/_}.conf"                 ### >>> MULTI <<<

backup_conf() {
    local f=$1; cp "$f" "${f}.$(date +%F-%H%M%S).bak"
    echo_info "已备份 $f"
}

insert_challenge_location() {
    local f=$1
    grep -qF '.well-known/acme-challenge' "$f" && return
    sed -i "/server_name.*$PRIMARY/a\    location /.well-known/acme-challenge/ { root $WEBROOT; }" "$f"    ### >>> MULTI <<<
    echo_info "插入 ACME location 到 $f"
}

# ---- 4.1 处理已有配置 ----------------------------------
patch_existing_conf() {
    local file=$1; echo_info "检测到已有同域名配置：$file"
    backup_conf "$file"

    # 4.1.a 确保 80 server 存在
    if ! grep -Poz "(?s)server\s*{[^}]*listen[^;]*\b80\b[^}]*server_name[^;]*\b$PRIMARY\b" "$file" &>/dev/null; then   ### >>> MULTI <<<
        echo_warning "原文件中缺少 80 端口，附加一个简易 80 server 块"
        cat >> "$file" <<EOF

# --- 自动附加 80 server (ACME) ---
server {
    listen 80;
    server_name ${DOMAINS[*]};      ### >>> MULTI <<<
    location /.well-known/acme-challenge/ { root $WEBROOT; }
}
EOF
    else
        insert_challenge_location "$file"
    fi

    # 4.1.b 处理 443 块 / 证书路径
    if grep -q "listen .*443" "$file"; then
        if grep -q "ssl_certificate " "$file"; then
            sed -i "s#ssl_certificate_key .*#ssl_certificate_key $NGINX_SSL_DIR/key.pem;#g" "$file"
            sed -i "s#ssl_certificate .*#ssl_certificate     $NGINX_SSL_DIR/fullchain.pem;#g" "$file"
        else
            sed -i "/listen .*443/a\    ssl_certificate     $NGINX_SSL_DIR/fullchain.pem;\n    ssl_certificate_key $NGINX_SSL_DIR/key.pem;" "$file"
        fi
    fi
}

# ---- 4.2 新建临时 / 正式配置 ---------------------------
generate_stage1_conf() {
cat > "$ACME_TEMP_CONF" <<EOF
# --- 自动生成，仅供 ACME http-01 --- ${DOMAINS[*]}   ### >>> MULTI <<<
server {
    listen 80;
    server_name ${DOMAINS[*]};     ### >>> MULTI <<<
    location /.well-known/acme-challenge/ { root $WEBROOT; }
}
EOF
echo_info "生成临时 ACME 配置 $ACME_TEMP_CONF"
}

generate_stage2_conf() {
cat > "$FINAL_CONF" <<EOF
# ===== ${DOMAINS[*]} =====            ### >>> MULTI <<<
server {
    listen 80;
    server_name ${DOMAINS[*]};         ### >>> MULTI <<<
    location /.well-known/acme-challenge/ { root $WEBROOT; }
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${DOMAINS[*]};         ### >>> MULTI <<<

    ssl_certificate     $NGINX_SSL_DIR/fullchain.pem;
    ssl_certificate_key $NGINX_SSL_DIR/key.pem;

    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    # ACME 续期仍需
    location /.well-known/acme-challenge/ { root $WEBROOT; }

    # 其他业务 location 请自行追加
}
EOF
echo_info "生成正式 HTTPS 配置 $FINAL_CONF"
}

EXIST_CONF=$(grep -Rsl "server_name.*\<${PRIMARY}\>" "$NGINX_CONF_DIR" /etc/nginx/sites-* 2>/dev/null || true)   ### >>> MULTI <<<

if [[ -n $EXIST_CONF ]]; then
    patch_existing_conf "$EXIST_CONF"
else
    generate_stage1_conf
fi

reload_nginx
echo_info "进入第一阶段 (仅 HTTP)，准备申请证书..."
# ========================================================

# ============ 5) 申请证书 ===============================
### >>> MULTI 部分：判定是否存在通配符域名 ###############
wildcard=false
for d in "${DOMAINS[@]}"; do
    [[ $d == \*.* ]] && wildcard=true && break
done

ISSUE_OK=0
if $wildcard ; then
    echo_info "检测到通配符域名 → DNS-01 方式"
    acme.sh --issue \
        $(printf -- '-d %s ' "${DOMAINS[@]}") \
        --dns dns_ali \
        --key-file       "$NGINX_SSL_DIR/key.pem" \
        --fullchain-file "$NGINX_SSL_DIR/fullchain.pem" \
        --reloadcmd      "bash -c '$(declare -f reload_nginx); reload_nginx'" \
    && ISSUE_OK=1
else
    acme.sh --issue \
        $(printf -- '-d %s ' "${DOMAINS[@]}") \
        --webroot "$WEBROOT" \
        --key-file       "$NGINX_SSL_DIR/key.pem" \
        --fullchain-file "$NGINX_SSL_DIR/fullchain.pem" \
        --reloadcmd      "bash -c '$(declare -f reload_nginx); reload_nginx'" \
    && ISSUE_OK=1
fi
### >>> MULTI 结束 #######################################

[[ $ISSUE_OK -eq 1 ]] || { echo_error "证书签发失败"; exit 1; }
echo_info "证书申请成功 -> $NGINX_SSL_DIR"
# ========================================================

# ============ 6) 二阶段：启用 HTTPS =====================
if [[ ! -f $FINAL_CONF ]]; then
    echo_info "第二阶段：写入 HTTPS 配置并删除临时文件"
    generate_stage2_conf
    rm -f "$ACME_TEMP_CONF"
fi

reload_nginx
echo_info "OK! 现在可以访问: https://${PRIMARY#\*.}"      ### >>> MULTI <<<