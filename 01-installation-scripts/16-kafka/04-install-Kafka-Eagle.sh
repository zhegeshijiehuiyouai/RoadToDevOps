#!/bin/bash
version=2.0.3
download_url=https://codeload.github.com/smartloli/kafka-eagle-bin/tar.gz/${version}
tgzfile=kafka-eagle-bin-${version}.tar.gz
src_dir=$(pwd)/00src00
kafka_eagle_port=8084

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

# 解压
function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
        exit 2
    fi
}

# 此download函数为定制，不要复制给其他脚本使用
function download_tar_gz(){
    download_file_name=${tgzfile}
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
                yum install -y wget
            fi 
            wget $2 -O ${tgzfile}
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
                    yum install -y wget
                fi
                wget $2 -O ${tgzfile}
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

function check_dir() {
    if [ -d $1 ];then
        echo_error 目录 $1 已存在，退出
        exit 2
    fi
}

function check_java(){
    java -version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到jdk，请先部署jdk
        exit 1
    fi
}

function project_echo() {
    echo_info
    echo "==================================================================================="
    echo "项目 github 地址：https://github.com/smartloli/kafka-eagle                         "
    echo "官网下载地址：http://download.kafka-eagle.org/                                     "
    echo "如果下载实在太慢，可将压缩包（.tar.gz）下载到本地，移动至与脚本同级目录后再执行脚本"
    echo "                             by https://github.com/zhegeshijiehuiyouai/RoadToDevOps"
    echo "==================================================================================="
    echo
}

function add_kafka_eagle_home_to_profile() {
    echo_info 配置环境变量
    echo "export KE_HOME=${back_dir}/kafka-eagle-web-${version}" >  /etc/profile.d/kafka-eagle.sh
    echo "export PATH=\$PATH:${back_dir}/kafka-eagle-web-${version}/bin" >> /etc/profile.d/kafka-eagle.sh
    echo_warning 由于bash特性限制，在本终端使用 ke.sh 命令，需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端执行命令
}

function config_ke() {
    echo_info 调整 Kafka Eagle 配置
    cd ${back_dir}/kafka-eagle-web-${version}
    sed -i 's#^kafka.eagle.url=.*#kafka.eagle.url=jdbc:sqlite:'${back_dir}'/kafka-eagle-web-'${version}'/db/ke.db#g' conf/system-config.properties
    sed -i 's/^cluster2.kafka.eagle.offset.storage=zk/#&/g' conf/system-config.properties
}

function show_summary() {
    echo_info 配置文件 ：kafka-eagle-web-${version}/conf/system-config.properties
    echo -e "\033[37m                  主要配置项：\033[0m"
    echo -e "\033[37m                      kafka.eagle.zk.cluster.alias        -- 管理kafka的zk集群分组别名（kafka eagle支持监控多组kafka）\033[0m"
    echo -e "\033[37m                      cluster1.zk.list                    -- zk的地址，格式：ip:port[/path]。如有多个，用逗号隔开。如果没有cluster2，可将cluster2注释掉\033[0m"
    echo -e "\033[37m                      kafka.eagle.webui.port              -- kafka eagle web服务的端口\033[0m"
    echo -e "\033[37m                      cluster1.kafka.eagle.offset.storage -- 消费者偏移量存储方式，0.9 版本之前的kafka存储在zk，之后的存储在kafka\033[0m"
    echo -e "\033[37m                      kafka xxxxx jdbc driver address     -- 数据库，默认sqlite，可改为mysql\033[0m"
    echo -e "\033[37m                  启动命令 ：ke.sh start\033[0m"
    echo_warning 首次启动前请自行配置好 zk 集群别名、zk 的地址，即 kafka.eagle.zk.cluster.alias、cluster1.zk.list，如无特殊需求，其余可保持默认
}

############# main #############
project_echo
check_java
download_tar_gz $src_dir download_url
bare_name=$(echo ${tgzfile} | awk -F".tar.gz" '{print $1}')
check_dir ${back_dir}/kafka-eagle-web-${version}
cd ${file_in_the_dir}
untar_tgz ${tgzfile}
cd ${bare_name}
tar xf kafka-eagle-web-${version}-bin.tar.gz
mv kafka-eagle-web-${version} ${back_dir}/kafka-eagle-web-${version}
cd ${file_in_the_dir}
rm -rf ${bare_name}
config_ke
add_kafka_eagle_home_to_profile
show_summary
