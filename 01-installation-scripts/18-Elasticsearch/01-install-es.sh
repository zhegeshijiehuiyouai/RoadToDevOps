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
        sed -i '/^http.port:.*/a# 与其它节点交互的端口' /etc/elasticsearch/elasticsearch.yml
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

install_by_yum