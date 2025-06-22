#!/bin/bash

EASYSEARCH_VERSION=1.13.0-2159
EASYSEARCH_HOME=/opt/easysearch
# 包下载目录
src_dir=$(pwd)/00src00
easysearch_port=9200
easysearch_transport_port=9300
data_dir=${EASYSEARCH_HOME}/data
log_dir=${EASYSEARCH_HOME}/logs
cluster_name=cluster-01
node_name=node-01
easysearch_yml_file=${EASYSEARCH_HOME}/config/easysearch.yml
download_url=https://release.infinilabs.com/easysearch/stable/bundle/easysearch-${EASYSEARCH_VERSION}-linux-amd64-bundle.tar.gz
# 其他
limits_conf_file=/etc/security/limits.conf

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

# 脚本执行用户检测
if [[ $(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

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
	true
fi

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

#-------------------------------------------------
function input_machine_ip_fun() {
    read input_machine_ip
    machine_ip=${input_machine_ip}
    if [[ ! $machine_ip =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
        echo_error 错误的ip格式，退出
        exit 1
    fi
}
function get_machine_ip() {
    ip a | grep -E "bond" &> /dev/null
    if [ $? -eq 0 ];then
        echo_warning 检测到绑定网卡（bond），请手动输入使用的 ip ：
        input_machine_ip_fun
    elif [ $(ip a | grep -E "inet.*e(ns|np|th).*[[:digit:]]+.*" | awk '{print $2}' | cut -d / -f 1 | wc -l) -gt 1 ];then
        echo_warning 检测到多个 ip，请手动输入使用的 ip ：
        input_machine_ip_fun
    else
        machine_ip=$(ip a | grep -E "inet.*e(ns|np|th).*[[:digit:]]+.*" | awk '{print $2}' | cut -d / -f 1)
    fi
}
#-------------------------------------------------

function gen_unitfile() {
    unit_file=/etc/systemd/system/easysearch.service
    easysearch_yml_file=${EASYSEARCH_HOME}/config/easysearch.yml
    echo_info 生成easysearch.service文件用于systemd控制
    cat > ${unit_file} << EOF
[Unit]
Description=Easysearch Service
After=network.target

[Service]
Type=forking
User=easysearch
Group=easysearch
WorkingDirectory=${EASYSEARCH_HOME}
ExecStart=${EASYSEARCH_HOME}/bin/easysearch -d
PrivateTmp=true
LimitNOFILE=65536
LimitNPROC=65536
LimitAS=infinity
LimitFSIZE=infinity
LimitMEMLOCK=infinity
TimeoutStopSec=0
KillSignal=SIGTERM
KillMode=process
SendSIGKILL=no
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

function config_easysearch() {
    get_machine_ip
    echo_info 调整 easysearch 配置
    sed -i 's/^#cluster.name:.*/cluster.name: '${cluster_name}'/g' ${easysearch_yml_file}
    sed -i 's/^#node.name:.*/node.name: '${node_name}'/g' ${easysearch_yml_file}
        grep "^path.data" ${easysearch_yml_file} &> /dev/null
    if [ $? -eq 0 ];then
        sed -i 's#^path.data:.*#path.data: '${data_dir}'#g' ${easysearch_yml_file}
    else
        sed -i '/^#path.data:.*/apath.data: '${data_dir}'' ${easysearch_yml_file}
    fi
    grep "^path.logs" ${easysearch_yml_file} &> /dev/null
    if [ $? -eq 0 ];then
        sed -i 's#^path.logs:.*#path.logs: '${log_dir}'#g' ${easysearch_yml_file}
    else
        sed -i '/^#path.logs:.*/apath.logs: '${log_dir}'' ${easysearch_yml_file}
    fi
    sed -i 's/^#http.port:.*/http.port: '${easysearch_port}'/g' ${easysearch_yml_file}
    sed -i 's/^#network.host:.*/network.host: 0.0.0.0/g' ${easysearch_yml_file}
    sed -i 's/^#discovery.seed_hosts:.*/discovery.seed_hosts: ["'${machine_ip}'"]/g' ${easysearch_yml_file}
    grep "http.cors.enabled:" ${easysearch_yml_file} &> /dev/null
    if [ $? -ne 0 ];then
        echo "#" >> ${easysearch_yml_file}
        echo "# 是否支持跨域" >> ${easysearch_yml_file}
        echo "http.cors.enabled: true" >> ${easysearch_yml_file}
    fi
    grep "http.cors.allow-origin:" ${easysearch_yml_file} &> /dev/null
    if [ $? -ne 0 ];then
        echo "http.cors.allow-origin: \"*\"" >> ${easysearch_yml_file}
    fi
    grep "transport.tcp.port" ${easysearch_yml_file} &> /dev/null
    if [ $? -ne 0 ];then
        sed -i '/^http.port:.*/atransport.tcp.port: '${easysearch_transport_port}'' ${easysearch_yml_file}
        sed -i '/^http.port:.*/a# 与其它节点沟通的端口' ${easysearch_yml_file}
        sed -i '/^http.port:.*/a#' ${easysearch_yml_file}
    else
        sed -i 's/^transport.tcp.port:.*/transport.tcp.port: '${easysearch_transport_port}'/g' ${easysearch_yml_file}
    fi
    sed -i '/^#node.attr.rack:.*/i# 自定义属性。创建索引时，可通过index.routing.allocation.awareness.attributes让es分配索引分片时考虑该属性' ${easysearch_yml_file}
    echo "" >> ${easysearch_yml_file}
    echo "# 单节点部署" >> ${easysearch_yml_file}
    echo "discovery.type: single-node" >> ${easysearch_yml_file}
    echo "# 缓冲区限制，防止OOM" >> ${easysearch_yml_file}
    echo "indices.fielddata.cache.size:  40%" >> ${easysearch_yml_file}
    echo "# 断路器限制，需要比indices.fielddata.cache.size大" >> ${easysearch_yml_file}
    echo "indices.breaker.fielddata.limit:  60%" >> ${easysearch_yml_file}
    

    echo "# 锁住内存，不使用swap，生产环境推荐开启" >> ${easysearch_yml_file}
    echo "bootstrap.memory_lock: true" >> ${easysearch_yml_file}
    # unitfile也要修改
    sed -i '/\[Install\]/i# 设置内存锁定\nLimitMEMLOCK=infinity\n' ${unit_file}
    # unitfile加了，那么${limits_conf_file}可以不加，但为了预防二进制部署时手动启动，还是加上
    # 确保幂等性，删除现有配置（如果有）
    sed -i "/### allow user 'easysearch' mlockall/d" ${limits_conf_file}
    sed -i "/^easysearch[[:space:]]*soft[[:space:]]*memlock/d" ${limits_conf_file}
    sed -i "/^easysearch[[:space:]]*hard[[:space:]]*memlock/d" ${limits_conf_file}
    cat >> ${limits_conf_file} << _EOF_
### allow user 'easysearch' mlockall
easysearch soft memlock unlimited
easysearch hard memlock unlimited
_EOF_
}

function echo_summary() {
    echo_info easysearch 已部署完毕，以下是相关信息：
    echo -e "\033[37m                  启动命令：systemctl start easysearch\033[0m"
     echo -e "\033[37m                  easysearch节点间通信地址：${machine_ip}:${easysearch_transport_port}\033[0m"
    if [[ ${enalbe_https_confirm_input} == "y" || ${enalbe_https_confirm_input} == "Y" ]];then
        echo -e "\033[37m                  easysearch服务地址：https://${machine_ip}:${easysearch_port}\033[0m"
        # 从 logs/initialize.log 文件中提取用户名和密码
        cred=$(grep -oP '@\s*\K\w+:\w+' ${EASYSEARCH_HOME}/logs/initialize.log)
        username=$(echo "$cred" | cut -d: -f1)
        password=$(echo "$cred" | cut -d: -f2)
        usage=$(grep -oP '@\s*Usage:\s*\K.*' ${EASYSEARCH_HOME}/logs/initialize.log |  sed 's/ *@$//')
        echo -e "\033[37m                  账号/密码：$username / $password\033[0m"
        echo -e "\033[37m                  用法：$usage\033[0m"
    else
        echo -e "\033[37m                  easysearch服务地址：http://${machine_ip}:${easysearch_port}\033[0m"
    fi
    echo

    echo
    echo_info "---下面配置只能通过接口更新，请待ES启动后执行---"
    echo_warning "注意，以下是针对索引的设置，需要集群中存在索引，没有索引时执行会报错"
    echo "创建索引：curl -X PUT 'http://localhost:${easysearch_port}/test_index'"
    echo "删除索引：curl -X DELETE 'http://127.0.0.1:${easysearch_port}/test_index'"
    echo
    cat << _EOF_
curl -X PUT 'http://127.0.0.1:9200/_all/_settings?preserve_existing=true' -H 'Content-Type: application/json' -d '{
    // 推迟节点离开集群后分片分配时间为20m（vivo经验）
    "index.unassigned.node_left.delayed_timeout": "20m",
    // 限制单个es中允许存在的字段（Field）总数，vivo经验20000（默认1000）
    "index.mapping.total_fields.limit" : "2000",
    // 索引刷新间隔，vivo经验：业务类1s（默认）；部分写入流量大调整为5s；日志类30s
    "index.refresh_interval" : "5s",
    // 异步刷盘，降低写入延迟（但可能丢失部分数据）
    "index.translog.durability" : "async",
    // 数据达到多少落盘，vivo经验1000m
    "index.translog.flush_threshold_size" : "1000m",
    // 数据落盘间隔，vivo经验90s
    "index.translog.sync_interval" : "90s"
}'
_EOF_
    echo
}

function enalbe_https_confirm() {
    read -p "请输入：" enalbe_https_confirm_input
    case ${enalbe_https_confirm_input} in
    y|Y)
        echo_info "初始化"
        cd ${EASYSEARCH_HOME} && bin/initialize.sh
        ;;
    n|N)
        sed -i 's/^security.enabled:.*/security.enabled: false/g' ${easysearch_yml_file}
        ;;
    *)
        echo_warning 请输入y或n
        enalbe_https_confirm
        ;;
    esac
}

function secure_initialize(){
    echo_info "是否开启https? [y/n]"
    enalbe_https_confirm
}

echo_info "创建 easysearch 用户"
groupadd -g 602 easysearch
useradd -u 602 -g easysearch -m -d /home/easysearch -c 'easysearch' -s /bin/bash easysearch

if [[ -d ${EASYSEARCH_HOME} ]]; then
    echo_error "目录 ${EASYSEARCH_HOME} 已存在，可能是之前安装过 Easysearch，请检查"
    exit 2
else
    echo_info "创建 easysearch 安装目录"
    mkdir -p ${EASYSEARCH_HOME}
fi

echo_info "开始下载 Easysearch ${EASYSEARCH_VERSION} 包"
download_tar_gz ${src_dir} ${download_url}
cd ${src_dir}
echo_info "解压 Easysearch ${EASYSEARCH_VERSION} 包"
tar -zxf easysearch-${EASYSEARCH_VERSION}-linux-amd64-bundle.tar.gz -C ${EASYSEARCH_HOME}

gen_unitfile
config_easysearch

secure_initialize

echo_info 调整目录权限
chown -R easysearch:easysearch ${EASYSEARCH_HOME}

echo_info "启动 Easysearch"
systemctl daemon-reload
systemctl start easysearch

echo_summary