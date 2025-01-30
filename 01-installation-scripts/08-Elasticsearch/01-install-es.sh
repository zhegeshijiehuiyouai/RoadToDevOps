#!/bin/bash
# 二进制和docker部署生效，yum部署时，选择该大版本的最新小版本
es_version=7.17.27
es_major_version=$(echo "$es_version" | cut -d '.' -f 1)
# 各种部署方式都适用的配置
es_port=9200
es_transport_port=9300
data_dir=/data/es.data
log_dir=/data/logs/elasticsearch    # docker部署不适用
cluster_name=cluster-01
node_name=node-01
# 启动用户和组，二进制、yum部署时使用
es_user=elasticsearch
es_group=elasticsearch
jvm_xms=1g
jvm_xmx=1g
# 二进制部署使用
src_dir=$(pwd)/00src00
deploy_dir=/data/elasticsearch-${es_version}


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

function check_dir() {
    if [ -d $1 ];then
        echo_error 检测到 $1 已存在，本机可能已部署elasticsearch，请检查。退出
        exit 2
    fi
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

function add_user_and_group(){
    if id -g ${1} >/dev/null 2>&1; then
        true
    else
        groupadd ${1}
        echo_info 创建${1}组
    fi

    if id -u ${2} >/dev/null 2>&1; then
        true
    else
        useradd -M -g ${1} -s /sbin/nologin ${2}
        echo_info 创建${2}用户
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

function config_es() {
    get_machine_ip
    echo_info 调整 elasticsearch 配置
    sed -i 's/^#cluster.name:.*/cluster.name: '${cluster_name}'/g' ${es_yml_file}
    sed -i 's/^#node.name:.*/node.name: '${node_name}'/g' ${es_yml_file}
    grep "^path.data" ${es_yml_file} &> /dev/null
    if [ $? -eq 0 ];then
        sed -i 's#^path.data:.*#path.data: '${data_dir}'#g' ${es_yml_file}
    else
        sed -i '/^#path.data:.*/apath.data: '${data_dir}'' ${es_yml_file}
    fi
    grep "^path.logs" ${es_yml_file} &> /dev/null
    if [ $? -eq 0 ];then
        sed -i 's#^path.logs:.*#path.logs: '${log_dir}'#g' ${es_yml_file}
    else
        sed -i '/^#path.logs:.*/apath.logs: '${log_dir}'' ${es_yml_file}
    fi
    sed -i 's/^#http.port:.*/http.port: '${es_port}'/g' ${es_yml_file}
    sed -i 's/^#network.host:.*/network.host: 0.0.0.0/g' ${es_yml_file}
    sed -i 's/^#discovery.seed_hosts:.*/discovery.seed_hosts: ["'${machine_ip}'"]/g' ${es_yml_file}
    grep "http.cors.enabled:" ${es_yml_file} &> /dev/null
    if [ $? -ne 0 ];then
        echo "#" >> ${es_yml_file}
        echo "# 是否支持跨域" >> ${es_yml_file}
        echo "http.cors.enabled: true" >> ${es_yml_file}
    fi
    grep "http.cors.allow-origin:" ${es_yml_file} &> /dev/null
    if [ $? -ne 0 ];then
        echo "http.cors.allow-origin: \"*\"" >> ${es_yml_file}
    fi
    grep "transport.tcp.port" ${es_yml_file} &> /dev/null
    if [ $? -ne 0 ];then
        sed -i '/^http.port:.*/atransport.tcp.port: '${es_transport_port}'' ${es_yml_file}
        sed -i '/^http.port:.*/a# 与其它节点沟通的端口' ${es_yml_file}
        sed -i '/^http.port:.*/a#' ${es_yml_file}
    else
        sed -i 's/^transport.tcp.port:.*/transport.tcp.port: '${es_transport_port}'/g' ${es_yml_file}
    fi
    sed -i '/^#node.attr.rack:.*/i# 自定义属性。创建索引时，可通过index.routing.allocation.awareness.attributes让es分配索引分片时考虑该属性' ${es_yml_file}
    echo "" >> ${es_yml_file}
    echo "# 单节点部署" >> ${es_yml_file}
    echo "discovery.type: single-node" >> ${es_yml_file}

    cat >> ${jvm_options_file} << _EOF_

########## 脚本添加 #########
-Xms${jvm_xms}
-Xmx${jvm_xmx}
_EOF_
}

function echo_summary() {
    echo_info elasticsearch 已部署完毕，以下是相关信息：
    echo -e "\033[37m                  启动命令：systemctl start elasticsearch\033[0m"
    echo -e "\033[37m                  es服务地址：http://${machine_ip}:${es_port}\033[0m"
    echo -e "\033[37m                  es节点间通信地址：${machine_ip}:${es_transport_port}\033[0m"
}

function is_installed_es() {
    ps -ef | grep elasticsearch | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测elasticsearch已在运行，退出
        exit 1
    fi
    if ss -lntu | grep ':'${es_port}' ' &> /dev/null;then
        echo_error ${es_port}端口被占用，退出
        exit 1
    fi
    if ss -lntu | grep ':'${es_transport_port}' ' &> /dev/null;then
        echo_error ${es_transport_port}端口被占用，退出
        exit 1
    fi
    if [ -d /etc/elasticsearch ];then
        echo_error 检测到 /etc/elasticsearch 目录，本机可能已部署了 elasticsearch，请退出检查
        exit 5
    fi
    check_dir ${log_dir}
    check_dir ${data_dir}
    add_user_and_group ${es_group} ${es_user}
}

function install_by_yum() {
    mkdir -p ${data_dir} ${log_dir}

    echo_info 配置 elasticsearch 仓库
    cat > /etc/yum.repos.d/elasticsearch.repo << EOF
[elasticsearch]
name=Elasticsearch repository for 7.x packages
baseurl=https://mirrors.bfsu.edu.cn/elasticstack/yum/elastic-7.x/
enable=1
gpgcheck=0
EOF
    echo_info 安装 elasticsearch
    yum install -y --enablerepo=elasticsearch elasticsearch
    if [ $? -ne 0 ];then
        echo_error 安装 elasticsearch 出错，退出
        exit 1
    fi
    sed -i 's#User=.*#User='${es_user}'#g' ${unit_file}
    sed -i 's#Group=.*#Group='${es_group}'#g' ${unit_file}
    systemctl daemon-reload
    config_es
    echo_info elasticsearch 目录授权
    chown -R ${es_user}:${es_group} ${log_dir}
    chown -R ${es_user}:${es_group} ${data_dir}
    echo_summary
}

function gen_unitfile() {
    echo_info 生成elasticsearch.service文件用于systemd控制
    cat > ${unit_file} << EOF
[Unit]
Description=Elasticsearch
Documentation=https://www.elastic.co
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
PrivateTmp=true

User=${es_user}
Group=${es_group}

ExecStart=${deploy_dir}/bin/elasticsearch

# StandardOutput is configured to redirect to journalctl since
# some error messages may be logged in standard output before
# elasticsearch logging system is initialized. Elasticsearch
# stores its logs in /var/log/elasticsearch and does not use
# journalctl by default. If you also want to enable journalctl
# logging, you can simply remove the "quiet" option from ExecStart.
StandardOutput=journal
StandardError=inherit

# Specifies the maximum file descriptor number that can be opened by this process
LimitNOFILE=65535

# Specifies the maximum number of processes
LimitNPROC=4096

# Specifies the maximum size of virtual memory
LimitAS=infinity

# Specifies the maximum file size
LimitFSIZE=infinity

# Disable timeout logic and wait until process is stopped
TimeoutStopSec=0

# SIGTERM signal is used to stop the Java process
KillSignal=SIGTERM

# Send the signal only to the JVM rather than its control group
KillMode=process

# Java process is never killed
SendSIGKILL=no

# When a JVM receives a SIGTERM signal it exits with code 143
SuccessExitStatus=143

# Allow a slow startup before the systemd notifier module kicks in to extend the timeout
TimeoutStartSec=900

[Install]
WantedBy=multi-user.target
EOF
}

function install_by_tgz() {
    download_tar_gz ${src_dir} https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${es_version}-linux-x86_64.tar.gz
    cd ${file_in_the_dir}
    untar_tgz elasticsearch-${es_version}-linux-x86_64.tar.gz
    mv elasticsearch-${es_version} ${deploy_dir}
    mkdir -p ${data_dir} ${log_dir}
    gen_unitfile
    config_es
    echo_info elasticsearch 目录授权
    chown -R ${es_user}:${es_group} ${log_dir}
    chown -R ${es_user}:${es_group} ${data_dir}
    chown -R ${es_user}:${es_group} ${deploy_dir}
    echo_summary
}

function is_run_docker_es() {
    docker version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 您尚未安装 docker，退出
        exit 3
    fi
    
    container_name=elasticsearch
    docker ps -a | awk '{print $NF}' | grep ${container_name} &>/dev/null
    if [ $? -eq 0 ];then
        echo_error 已存在 ${container_name} 容器，退出
        exit 4
    fi
}

function install_by_docker() {
    is_run_docker_es
    docker_echo_flag=0
    if [ -d ${data_dir} ];then
        docker_echo_flag=1
    fi

    [ -f /etc/timezone ] || echo "Asia/Shanghai" > /etc/timezone

    echo -e -n "容器id  ："
    docker run -d --hostname ${container_name} \
               --name ${container_name} \
               -v /etc/localtime:/etc/localtime \
               -v /etc/timezone:/etc/timezone \
               -e TAKE_FILE_OWNERSHIP=111 \
               -v ${data_dir}:/usr/share/elasticsearch/data \
               -p ${es_port}:9200 \
               -p ${es_transport_port}:9300 \
               -e "discovery.type=single-node" \
               elasticsearch:${es_version}
    echo 容器name：${container_name}

    echo_info Elasticsearch 已部署，信息如下：
    echo -e "\033[37m                  启动命令：docker start ${container_name}\033[0m"
    echo -e "\033[37m                  es服务地址：http://${machine_ip}:${es_port}\033[0m"
    echo -e "\033[37m                  es节点间通信地址：${machine_ip}:${es_transport_port}\033[0m"
    # 如果存在数据目录，则提示一下
    if [ ${docker_echo_flag} -eq 1 ];then
        echo_warning 此次运行的容器使用了之前存在的 elasticsearch 目录 ${data_dir}
    fi
}



function install_main_func(){
    read -p "请输入数字选择安装类型（如需退出请输入q）：" -e software
    case $software in
        1)
            unit_file=/etc/systemd/system/elasticsearch.service
            es_yml_file=${deploy_dir}/config/elasticsearch.yml
            jvm_options_file=${deploy_dir}/config/jvm.options
            is_installed_es
            echo_info 即将使用 二进制包 部署elasticsearch
            # 等待1秒，给用户手动取消的时间
            sleep 1
            install_by_tgz
            ;;
        2)
            unit_file=/usr/lib/systemd/system/elasticsearch.service
            es_yml_file=/etc/elasticsearch/elasticsearch.yml
            jvm_options_file=/etc/elasticsearch/jvm.options
            is_installed_es
            echo_info 即将使用 yum 部署elasticsearch
            sleep 1
            install_by_yum
            ;;
        3)
            is_run_docker_es
            echo_info 即将使用 docker 部署elasticsearch
            sleep 1
            install_by_docker
            ;;
        q|Q)
            exit 0
            ;;
        *)
            install_main_func
            ;;
    esac
}

echo -e "\033[31m本脚本支持三种部署方式：\033[0m"
echo -e "\033[36m[1]\033[32m 二进制包部署elasticsearch （${es_version}）\033[0m"
echo -e "\033[36m[2]\033[32m yum部署elasticsearch（${es_major_version}.x 最新版）\033[0m"
echo -e "\033[36m[3]\033[32m docker部署elasticsearch（${es_version}）\033[0m"
install_main_func