#!/bin/bash
# 可根据需要选择部署nginx、tengine

# 默认版本
nginx_default_version=1.26.1
tengine_default_version=3.1.0
# 所有需要下载的文件都下载到当前目录下的${src_dir}目录中
src_dir=00src00
mydir=$(pwd)

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

# 检测操作系统
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
    # 阻止配置更新弹窗
    export UCF_FORCE_CONFFOLD=1
    # 阻止应用重启弹窗
    export NEEDRESTART_SUSPEND=1
elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)
elif [[ -e /etc/almalinux-release ]]; then
    os="alma"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/almalinux-release)
else
	echo_error 不支持的操作系统
	exit 99
fi

function get_latest_version() {
    echo_info 从官网获取最新版本中

    # 设置dns超时时间，避免没网情况下等很久
    curl_timeout=3
    echo "options timeout:${curl_timeout} attempts:1 rotate" >> /etc/resolv.conf
    if [[ $tag == 'nginx' ]];then
        nginx_version=$(curl -sS  --connect-timeout ${curl_timeout} http://nginx.org/en/download.html | grep -oP 'Stable version.*?nginx-\K[0-9.]+' | sed 's/.$//')
        # 接口正常，[ ! ${nginx_version} ]为1；接口失败，[ ! ${nginx_version} ]为0
        if [ ! ${nginx_version} ];then
            echo_error nginx接口访问超时，使用默认版本：${nginx_default_version}
            nginx_version=${nginx_default_version}
        fi
        echo_info "nginx最新稳定版本：${nginx_version}"
    elif [[ $tag == 'tengine' ]];then
        tengine_version=$(curl -sS --connect-timeout ${curl_timeout} http://tengine.taobao.org/changelog_cn.html | awk -F'class="article-entry"' '{print $2}' | awk -F'id="Tengine' '{print $2}' | grep -oE "\".*\"" | grep -oE "title=.*" | awk -F"-" '{print $2}' | awk '{print $1}')
        # 接口正常，[ ! ${tengine_version} ]为1；接口失败，[ ! ${tengine_version} ]为0
        if [ ! ${tengine_version} ];then
            echo_error tengine接口访问超时，使用默认版本：${tengine_default_version}
            tengine_version=${tengine_default_version}
        fi
        echo_info "tengine最新版本：${tengine_version}"
    fi
    # 删除刚刚插入的最后一行
    sed -i '$d' /etc/resolv.conf
}


# 首先判断当前目录是否有压缩包：
#   I. 如果有压缩包，那么就在当前目录解压；
#   II.如果没有压缩包，那么就检查有没有 ${src_dir} 表示的目录;
#       1) 如果有目录，那么检查有没有压缩包
#           ① 有压缩包就解压
#           ② 没有压缩包则下载压缩包
#       2) 如果没有,那么就创建这个目录，然后 cd 到目录中，然后下载压缩包，然
#       后解压
# 解压的步骤都在后面，故此处只做下载

# 语法： download_tar_gz 保存的目录 下载链接
# 使用示例： download_tar_gz /data/openssh-update https://mirrors.cloud.tencent.com/openssl/source/openssl-1.1.1h.tar.gz
function check_downloadfile() {
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IksS $1 | head -1 | awk '{print $2}')
    if [ $http_code -eq 404 ];then
        echo_error $1
        echo_error 服务端文件不存在，退出
        exit 98
    fi
}
function download_tar_gz(){
    download_file_name=$(echo $2 |  awk -F"/" '{print $NF}')
    back_dir=$(pwd)
    file_in_the_dir=''  # 这个目录是后面编译目录的父目录

    ls $download_file_name &> /dev/null
    if [ $? -ne 0 ];then
        # 进入此处表示脚本所在目录没有压缩包
        ls -d $1 &> /dev/null
        if [ $? -ne 0 ];then
            # 进入此处表示没有${src_dir}目录
            mkdir -p $1 && cd $1
            echo_info 下载 $download_file_name 至 $(pwd)/
            # 检测是否有wget工具
            if [ ! -f /usr/bin/wget ];then
                echo_info 安装wget工具
                if [[ $os == "centos" ]];then
                    yum install -y wget
                elif [[ $os == "ubuntu" ]];then
                    apt install -y wget
                elif [[ $os == 'rocky' || $os == 'alma' ]];then
                    dnf install -y wget
                fi
            fi
            check_downloadfile $2
            wget --no-check-certificate $2
            if [ $? -ne 0 ];then
                echo_error 下载 $2 失败！
                exit 1
            fi
            file_in_the_dir=$(pwd)
            # 返回脚本所在目录，这样这个函数才可以多次使用
            cd ${back_dir}
        else
            # 进入此处表示有${src_dir}目录
            cd $1
            ls $download_file_name &> /dev/null
            if [ $? -ne 0 ];then
            # 进入此处表示${src_dir}目录内没有压缩包
                echo_info 下载 $download_file_name 至 $(pwd)/
                # 检测是否有wget工具
                if [ ! -f /usr/bin/wget ];then
                    echo_info 安装wget工具
                    if [[ $os == "centos" ]];then
                        yum install -y wget
                    elif [[ $os == "ubuntu" ]];then
                        apt install -y wget
                    elif [[ $os == 'rocky' || $os == 'alma' ]];then
                        dnf install -y wget
                    fi
                fi
                check_downloadfile $2
                wget --no-check-certificate $2
                if [ $? -ne 0 ];then
                    echo_error 下载 $2 失败！
                    exit 1
                fi
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            else
                # 进入此处，表示${src_dir}目录内有压缩包
                echo_info 发现压缩包$(pwd)/$download_file_name
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            fi
        fi
    else
        # 进入此处表示脚本所在目录有压缩包
        echo_info 发现压缩包$(pwd)/$download_file_name
        file_in_the_dir=$(pwd)
    fi
}


# 根据$1判断下载什么应用
function download() {
    case $1 in
        nginx)
            download_tar_gz ${src_dir} http://nginx.org/download/$2
            ;;
        tengine)
            download_tar_gz ${src_dir} https://tengine.taobao.org/download/$2
            ;;
        *)
            echo_error 你下载了个寂寞
            exit 3
            ;;
    esac
}

# 解压
function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
        exit 2
    fi
}

# 多核编译
function multi_core_compile(){
    # 检查make存不存在
    make --version &> /dev/null
    if [ $? -ne 0 ];then
        if [[ $os == "centos" ]];then
            yum install -y make
        elif [[ $os == "ubuntu" ]];then
            apt install -y make
        elif [[ $os == "rocky" || $os == 'alma' ]];then
            dnf install -y make
        fi
    fi
    assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
    cpucores=$(cat /proc/cpuinfo | grep -c processor)
    compilecore=$(($cpucores - $assumeused - 1))
    if [ $compilecore -ge 1 ];then
        make -j $compilecore && make -j $compilecore install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi
    else
        make && make install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi 
    fi
}

function add_user_and_group(){
    if id -g ${1} >/dev/null 2>&1; then
        echo_warning ${1}组已存在，无需创建
    else
        groupadd ${1}
        echo_info 创建${1}组
    fi
    if id -u ${1} >/dev/null 2>&1; then
        echo_warning ${1}用户已存在，无需创建
    else
        useradd -M -g ${1} -s /sbin/nologin ${1}
        echo_info 创建${1}用户
    fi
}

function use_default_or_latest_version() {
    read -p "是否联网获取最新版本[y/n]（默认y）：" -e online_version
    online_version=${online_version:=y} # 如果用户没有输入，就使用默认值y
    case $online_version in
        y|Y)
            return 2
            ;;
        n|N)
            return 1
            ;;
        q|Q)
            echo_info "用户手动退出"
            exit 0
            ;;
        *)
            use_default_or_latest_version
            ;;
    esac
}

# 编译安装Nginx
function install_nginx(){
    # 用tag标识部署什么，后续脚本中调用
    tag=nginx
    # 部署目录
    installdir=${mydir}/${tag}

    use_default_or_latest_version
    result=$?
    # 使用默认返回1，使用最新返回2
    if [ $result -eq 1 ];then
        nginx_version=${nginx_default_version}
        echo_info "使用默认版本：${nginx_version}"
    elif [ $result -eq 2 ];then
        get_latest_version
    else
        echo_error "use_default_or_latest_version函数返回参数错误，退出"
        exit 20
    fi

    download ${tag} ${tag}-${nginx_version}.tar.gz
    cd ${file_in_the_dir}
    untar_tgz ${tag}-${nginx_version}.tar.gz

    echo_info 安装依赖程序
    if [[ $os == "centos" ]];then
        yum install -y gcc zlib zlib-devel openssl openssl-devel pcre pcre-devel
    elif [[ $os == "ubuntu" ]];then
        apt install -y gcc zlib1g zlib1g-dev openssl libssl-dev libpcre3 libpcre3-dev
    elif [[ $os == "rocky" || $os == 'alma' ]];then
        dnf install -y gcc zlib zlib-devel openssl openssl-devel pcre pcre-devel
    fi


    add_user_and_group ${tag}
    cd ${tag}-${nginx_version}
    # 修改server_token
    server_token_name=webserver-${nginx_version}
    sed -i 's@#define NGINX_VER          "nginx/" NGINX_VERSION@#define NGINX_VER          "'${server_token_name}'"@' src/core/nginx.h

    echo_info 配置编译参数
    ./configure --prefix=${installdir} --user=${tag} --group=${tag} --with-pcre --with-http_ssl_module --with-http_v2_module --with-stream --with-http_stub_status_module
    echo_info 多核编译
    multi_core_compile

    echo
    echo_info 优化nginx.conf
    worker_connections=$(expr 65535 / $cpucores)
cat > ${installdir}/conf/nginx.conf << EOF
#user  nginx;
###########CPU核心数######################
worker_processes    auto;
#########为每个nginx进程分配CPU,利用多核心优势########
worker_cpu_affinity    auto;
########进程打开的最多文件描述符数目#########
worker_rlimit_nofile 65535;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

pid         ${installdir}/logs/nginx.pid;


events {
    worker_connections  ${worker_connections};
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  logs/access.log  main;

    # 因为我们修改了server_token，所以这行要注释掉，如果指定了off，那么即使修改了，还是会显示nginx，这和nginx取值的逻辑有关
    # 详见 https://blog.csdn.net/Leopard_89/article/details/50778477
    # server_tokens off;

##############使用代理服务器的XFF信息作为remote_addr################
    # 当Nginx处在SLB后面时，就会把remote_addr设为SLB的IP，这个值其实是毫无意义的，可以通过nginx的realip模块，让它使用
    # x_forwarded_for里的值。使用这个模块需要重新编译Nginx，增加--with-http_realip_module参数
    #下面的配置就是把从10.64.0.0/10（云服务商专用网段）这一网段过来的请求全部使用X-Forwarded-For里的头信息作为remote_addr
#   set_real_ip_from    10.64.0.0/10;
#   real_ip_header    X-Forwarded-For;

#########允许请求头header中包含下划线##############
    # underscores_in_headers on;

#######################gzip压缩功能设置###############################
#########禁止nginx页面返回版本信息##############
    gzip on; #开启Gzip
    gzip_min_length 1k; #不压缩临界值，大于1K的才压缩，一般不用改
    gzip_buffers    4 16k; #缓冲
    gzip_http_version 1.0; #默认是HTTP/1.1，但用了反向代理的话，那么nginx和后端的upstream server之间默认是用HTTP/1.0协议通信的，为了反向代理能压缩，所以设置
    gzip_comp_level 3; #压缩级别，1-10，数字越大压缩的越好，时间也越长，看心情随便改吧
    gzip_types text/plain application/x-javascript text/css application/xml application/javascript application/x-font-woff image/jpeg image/gif image/png; ###进行压缩的文件类型.
    gzip_vary on; #跟Squid等缓存服务有关，on的话会在Header里增加"Vary: Accept-Encoding"
    gzip_disable "MSIE [1-6]\."; #IE6对Gzip不怎么友好，不给它Gzip了
#########实现文件传输性能提升###################
#    sendfile        on;  #开启gzip后，sendfile无效
#########在keepalive启用情况下提升网络性能##########
#    tcp_nopush     on;    # 已开启gzip，sendfile失效，故tcp_nopush失效
    tcp_nodelay    off;

    keepalive_timeout  30;

##############前台文件上传大小限制################
    client_max_body_size 200M;
##############在客户端停止响应之后,允许服务器关闭连接,释放socket关联的内存#############
    reset_timedout_connection on; 
##############设置客户端的响应超时时间.如果客户端停止读取数据,在这么多时间之后就释放过期的客户端连接###############
    send_timeout 10;
################分页面大小##########
    client_header_buffer_size 4k;
################缓存文件描述符和文件信息，提高文件的读取效率############
    open_file_cache max=65535 inactive=20s;  # 如果注释掉这句，后面的也就失效了
    open_file_cache_valid 30s;  #缓存检查频率
    open_file_cache_min_uses 2;  #缓存时间（20s）内的最少使用次数-未超过则移除
    open_file_cache_errors on;  #是否开启缓存错误信息
################请求超时时间设置################
    client_header_timeout 10; 
    client_body_timeout 10;
##################限制每个IP&每个server的并发连接数#############
#    limit_conn_zone \$binary_remote_addr zone=addr:10m;
#    limit_conn addr 20;
##########性能配置项，按照实际情况适当调整#########
    fastcgi_connect_timeout 1000;
    fastcgi_send_timeout 1000;
    fastcgi_read_timeout 1000;
##########用于反向代理时的缓存服务器功能，将后端服务器的响应缓存下来，减轻后端压力（缓存服务器）################
    # proxy_cache_path /data/nginx/cache levels=1:2 keys_zone=cache_one:10m max_size=1G inactive=1d; 
#########获取真实IP访问头######################    
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
#################反向代理配置##############
    # proxy_headers_hash_max_size 1024;
    # proxy_headers_hash_bucket_size 128;
##############开启websocket代理功能#############
    map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
    }
################使用ssi###################
    ssi on;
    ssi_silent_errors off;
    ssi_types text/shtml;

#############该server作用为防恶意解析#####
    server { 
        listen 80 default;
        # 如果https也需要防恶意解析，则将本server中的注释取消
        # listen 443 default_server ssl;
        server_name _;

        # ssl_certificate /data/nginx/ssl/www.xxx.com/www.crt; #随便设置一个ssl证书;
        # ssl_certificate_key /data/nginx/ssl/www.xxx.com/www.key; #随便设置一个ssl证书的key;
        # ssl_session_timeout 5m;
        # ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
        # ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
        # ssl_prefer_server_ciphers on;

        return 403;
    }

#############http转https#########
#    server {
#        listen  80;
#        server_name xxx;
#        location / {
#            # 不要将request_uri换为uri，这样将存在漏洞。可通过传入%0d%0a传入换行符，控制响应头及响应体。
#            return 302 https://$host$request_uri;
#        }
#    }

    server {
        listen       80;
        server_name  your_domain;

        charset utf-8;
################日志切割################
        if (\$time_iso8601 ~ "^(\d{4})-(\d{2})-(\d{2})")
        {
            set \$ng_year \$1;
            set \$ng_month \$2;
            set \$ng_day \$3;
        }
        access_log  logs/your_domain-\$ng_year\$ng_month\$ng_day.access.log;
        error_log logs/your_domain.error.log;
        
#-------------------- IP白名单 -----------------
#        allow 123.123.123.123;
#        allow 124.124.124.124;
#
#        deny all;
#------------------------------------------------

        location / {
            root   html;
            index  index.html index.htm;
        }

############显示目录######### 
#         location /show_dir/ {
#             autoindex on;
#             # autoindex_format json; # 默认html
#             autoindex_localtime on; # 使用服务器文件时间作为显示时间，仅在autoindex_format为html时生效
#         }

#########反向代理简单配置
#        location /proxy_url/ {
#            proxy_pass http://ip:port/proxy_url/;
#            #这个头有时很关键
#            proxy_set_header Host $http_host;
#        }


        #error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        #
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }

        # proxy the PHP scripts to Apache listening on 127.0.0.1:80
        #
        #location ~ \.php\$ {
        #    proxy_pass   http://127.0.0.1;
        #}

        # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
        #
        #location ~ \.php\$ {
        #    root           html;
        #    fastcgi_pass   127.0.0.1:9000;
        #    fastcgi_index  index.php;
        #    fastcgi_param  SCRIPT_FILENAME  /scripts\$fastcgi_script_name;
        #    include        fastcgi_params;
        #}

        # deny access to .htaccess files, if Apache's document root
        # concurs with nginx's one
        #
        #location ~ /\.ht {
        #    deny  all;
        #}
    }


    # another virtual host using mix of IP-, name-, and port-based configuration
    #
    #server {
    #    listen       8000;
    #    listen       somename:8080;
    #    server_name  somename  alias  another.alias;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}


    # HTTPS server
    #
    #server {
    #    listen       443 ssl;
    #    server_name  localhost;

    # ssl_certificate /data/nginx/ssl/www.xxx.com/www.crt; #ssl证书;
    # ssl_certificate_key /data/nginx/ssl/www.xxx.com/www.key; #ssl证书的key;
    # ssl_session_timeout 5m;
    # ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    # ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;
    # ssl_prefer_server_ciphers on;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}
    include conf.d/*.conf;
}
EOF

    echo_info 创建自配置目录
    mkdir -p ${installdir}/conf/conf.d
    chown -R ${tag}:${tag} ${installdir}

    echo_info 设置nginx配置文件语法高亮显示
    [ -d ~/.vim ] || mkdir -p ~/.vim
    \cp -rf contrib/vim/* ~/.vim/

    # 清理包
    cd ${installdir}
    rm -rf ${file_in_the_dir}/${tag}-${nginx_version}

    echo_info 生成nginx.service文件用于systemd控制
cat > /etc/systemd/system/nginx.service <<EOF
[Unit]
Description=The nginx HTTP and reverse proxy server
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
# PIDFile=${installdir}/logs/nginx.pid
# Nginx will fail to start if /run/nginx.pid already exists but has the wrong
# SELinux context. This might happen when running \`nginx -t\` from the cmdline.
# https://bugzilla.redhat.com/show_bug.cgi?id=1268621
ExecStartPre=/usr/bin/rm -f ${installdir}/logs/nginx.pid
ExecStartPre=${installdir}/sbin/nginx -t
ExecStart=${installdir}/sbin/nginx
ExecReload=${installdir}/sbin/nginx -s reload
KillSignal=SIGQUIT
TimeoutStopSec=5
KillMode=process
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

    echo_info Nginx已安装在 ${installdir}
    echo_info 启动命令：
    echo -e "\033[37m                  systemctl start nginx\033[0m"
}

# 编译安装tengine
function install_tengine(){
    # 用tag标识部署什么，后续脚本中调用
    tag=tengine
    # 部署目录
    installdir=${mydir}/${tag}

    use_default_or_latest_version
    result=$?
    # 使用默认返回1，使用最新返回2
    if [ $result -eq 1 ];then
        tengine_version=${tengine_default_version}
        echo_info "使用默认版本：${tengine_version}"
    elif [ $result -eq 2 ];then
        get_latest_version
    else
        echo_error "use_default_or_latest_version函数返回参数错误，退出"
        exit 20
    fi

    download ${tag} ${tag}-${tengine_version}.tar.gz
    cd ${file_in_the_dir}
    untar_tgz ${tag}-${tengine_version}.tar.gz

    echo_info 安装依赖程序
    if [[ $os == "centos" ]];then
        yum install -y gcc zlib zlib-devel openssl openssl-devel pcre pcre-devel
    elif [[ $os == "ubuntu" ]];then
        apt install -y gcc zlib1g zlib1g-dev openssl libssl-dev libpcre3 libpcre3-dev
    elif [[ $os == "rocky" || $os == 'alma' ]];then
        dnf install -y gcc zlib zlib-devel openssl openssl-devel pcre pcre-devel
    fi

    add_user_and_group ${tag}
    cd ${tag}-${tengine_version}
    echo_info 配置编译参数
    ./configure --prefix=${installdir} --user=${tag} --group=${tag} --with-pcre --with-http_ssl_module --with-http_v2_module --with-stream --with-http_stub_status_module
    echo_info 多核编译
    multi_core_compile

    # 清理包
    cd ${installdir}
    rm -rf ${file_in_the_dir}/${tag}-${tengine_version}

    echo
    echo_info 设置tengine配置文件语法高亮显示
    [ -d ~/.vim ] || mkdir -p ~/.vim
    \cp -rf contrib/vim/* ~/.vim/

    # 清理包
    cd ${installdir}
    rm -rf ${file_in_the_dir}/${tag}-${nginx_version}

    echo_info 生成tengine.service文件用于systemd控制
cat > /etc/systemd/system/tengine.service <<EOF
[Unit]
Description=The Tengine HTTP and reverse proxy server
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=${installdir}/logs/nginx.pid
# Nginx will fail to start if /run/nginx.pid already exists but has the wrong
# SELinux context. This might happen when running \`nginx -t\` from the cmdline.
# https://bugzilla.redhat.com/show_bug.cgi?id=1268621
ExecStartPre=/usr/bin/rm -f ${installdir}/logs/nginx.pid
ExecStartPre=${installdir}/sbin/nginx -t
ExecStart=${installdir}/sbin/nginx
ExecReload=/bin/kill -s HUP \$MAINPID
KillSignal=SIGQUIT
TimeoutStopSec=5
KillMode=process
PrivateTmp=true
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

    echo
    echo_info tengine已安装在 ${installdir}
    echo_info 启动命令：
    echo -e "\033[37m                  systemctl start tengine\033[0m"
}


function install_main_func(){
    read -p "请输入数字选择要安装的服务（如需退出请输入q）：" -e software
    case $software in
        1)
            echo_info 即将安装 nginx
            # 等待1秒，给用户手动取消的时间
            sleep 1
            install_nginx
            ;;
        2)
            echo_info 即将安装 tengine
            sleep 1
            install_tengine
            ;;
        q|Q)
            echo_info "用户手动退出"
            exit 0
            ;;
        *)
            install_main_func
            ;;
    esac
}

echo -e "\033[32m本脚本支持一键部署：\033[0m"
echo -e "\033[36m[1]\033[32m nginx     - 编译安装\033[0m"
echo -e "\033[36m[2]\033[32m tengine   - 编译安装\033[0m"
install_main_func
