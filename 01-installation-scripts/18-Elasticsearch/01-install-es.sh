#!/bin/bash
es_home=/data/elasticsearch
es_port=9200
es_transport_port=9300

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
        echo_error 目录 $1 已存在，退出
        exit 2
    fi
}

function config_es() {
    echo_info 调整 elasticsearch 配置
    grep "可以设置多个存储路径" /etc/elasticsearch/elasticsearch.yml &> /dev/null
    if [ $? -ne 0 ];then
        sed -i '/^path.data:.*/i# 可以设置多个存储路径，用逗号隔开' /etc/elasticsearch/elasticsearch.yml
    fi
    sed -i 's#^path.data:.*#path.data: '${es_home}'/data#g' /etc/elasticsearch/elasticsearch.yml
    sed -i 's#^path.logs:.*#path.logs: '${es_home}'/logs#g' /etc/elasticsearch/elasticsearch.yml
    sed -i 's/^#http.port:.*/http.port: '${es_port}'/g' /etc/elasticsearch/elasticsearch.yml
    grep "http.cors.enabled:" /etc/elasticsearch/elasticsearch.yml &> /dev/null
    if [ $? -ne 0 ];then
        echo "#" >> /etc/elasticsearch/elasticsearch.yml
        echo "# 是否支持跨域" >> /etc/elasticsearch/elasticsearch.yml
        echo "http.cors.enabled: true" >> /etc/elasticsearch/elasticsearch.yml
    fi
    grep "http.cors.allow-origin:" /etc/elasticsearch/elasticsearch.yml &> /dev/null
    if [ $? -ne 0 ];then
        echo "http.cors.allow-origin: \"*\"" >> /etc/elasticsearch/elasticsearch.yml
    fi
    grep "transport.tcp.port" /etc/elasticsearch/elasticsearch.yml &> /dev/null
    if [ $? -ne 0 ];then
        sed -i '/^http.port:.*/atransport.tcp.port: '${es_transport_port}'' /etc/elasticsearch/elasticsearch.yml
        sed -i '/^http.port:.*/a# 与其它节点沟通的端口' /etc/elasticsearch/elasticsearch.yml
        sed -i '/^http.port:.*/a#' /etc/elasticsearch/elasticsearch.yml
    else
        sed -i 's/^transport.tcp.port:.*/transport.tcp.port: '${es_transport_port}'/g' /etc/elasticsearch/elasticsearch.yml
    fi
    
}

function echo_summary() {
    echo_info elasticsearch 已部署完毕，以下是相关信息：
    echo -e "\033[37m                  启动命令：systemctl start elasticsearch\033[0m"
    echo -e "\033[37m                  端口：${es_port}\033[0m"
    echo -e "\033[37m                  与其他节点通信端口：${es_transport_port}\033[0m"
}

function is_installed_es() {
    ps -ef | grep elasticsearch | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到本机上已部署 elasticsearch，退出
        exit 1
    fi
    if [ -d /etc/elasticsearch ];then
        echo_error 检测到 /etc/elasticsearch 目录，本机可能已部署了 elasticsearch，请退出检查
        exit 5
    fi
    if [ -d ${es_home} ];then
        echo_error 检测到 ${es_home} 目录，本机可能已部署了 elasticsearch，请退出检查
        exit 6
    fi
}

function install_by_yum() {
    check_dir ${es_home}
    echo_info 创建数据目录 ${es_home}
    mkdir -p ${es_home}/{data,logs}

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
    echo_info elasticsearch 数据目录授权
    chown -R elasticsearch:elasticsearch ${es_home}
    config_es
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
    if [ -d ${rabbitmq_home} ];then
        docker_echo_flag=1
    fi

    [ -f /etc/timezone ] || echo "Asia/Shanghai" > /etc/timezone

    echo -e -n "容器id  ："
    docker run -d --hostname ${container_name} \
               --name ${container_name} \
               -v /etc/localtime:/etc/localtime \
               -v /etc/timezone:/etc/timezone \
               -e TAKE_FILE_OWNERSHIP=111 \
               -v ${es_home}/data:/usr/share/elasticsearch/data \
               -p ${es_port}:9200 \
               -p ${es_transport_port}:9300 \
               -e "discovery.type=single-node" \
               elasticsearch:7.10.1
    echo 容器name：${container_name}

    echo_info Elasticsearch 已部署，信息如下：
    echo -e "\033[37m                  启动命令：docker start ${container_name}\033[0m"
    echo -e "\033[37m                  elasticsearch 端口：${es_port}\033[0m"
    echo -e "\033[37m                  elasticsearch 节点间通信端口：${es_transport_port}\033[0m"
    # 如果存在数据目录，则提示一下
    if [ ${docker_echo_flag} -eq 1 ];then
        echo_warning 此次运行的容器使用了之前存在的 elasticsearch 目录 ${es_home}
    fi
}



function install_main_func(){
    read -p "请输入数字选择安装类型（如需退出请输入q）：" software
    case $software in
        1)
            # 安装前先判断是否已经安装了rabbitmq
            is_installed_es
            echo_info 即将使用 yum 安装elasticsearch
            # 等待1秒，给用户手动取消的时间
            sleep 1
            install_by_yum
            ;;
        2)
            is_run_docker_es
            echo_info 即将使用 docker 安装elasticsearch
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

echo -e "\033[31m本脚本支持两种部署方式：\033[0m"
echo -e "\033[36m[1]\033[32m yum安装elasticsearch\033[0m"
echo -e "\033[36m[2]\033[32m docker安装elasticsearch\033[0m"
install_main_func