#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
tomcat_version=8.5.64
# tomcat部署的目录，如果要部署多个tomcat在同一台服务器，可修改此变量
tomcat_home=$(pwd)/tomcat-${tomcat_version}
tomcat_shutdown_port=8005
tomcat_http_port=8080
# 启动服务的用户
sys_user=tomcat
unit_file_name=tomcat.service
# 内存配置
Xms=512M
Xmx=1024M

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
        exit 1
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
function download_tar_gz(){
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IsS $2 | head -1 | awk '{print $2}')
    if [ $http_code -eq 404 ];then
        echo_error $2
        echo_error 服务端文件不存在，退出
        exit 98
    fi
    
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
                yum install -y wget
            fi
            wget $2
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
                    yum install -y wget
                fi
                wget $2
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

function is_run_tomcat() {
    java -version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到java，请先部署java
        exit 2
    fi

    ps -ef | grep ${tomcat_home} | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到tomcat正在运行中，退出
        exit 3
    fi
    if [ -d ${tomcat_home} ];then
        echo_error 检测到目录 ${tomcat_home}，请检查是否重复安装，退出
        exit 4
    fi
}

function generate_unit_file_and_start() {
    echo_info 生成${unit_file_name}文件用于systemd控制
    cat >/usr/lib/systemd/system/${unit_file_name} <<EOF
[Unit]
Description=Apache Tomcat Web Application Container -- script from https://github.com/zhegeshijiehuiyouai/RoadToDevOps
After=syslog.target network.target

[Service]
Type=forking

Environment=JAVA_HOME=$JAVA_HOME
Environment=CATALINA_HOME=${tomcat_home}
Environment=CATALINA_BASE=${tomcat_home}
Environment='CATALINA_OPTS=-Xms${Xms} -Xmx${Xmx} -server -XX:+UseParallelGC -Djava.awt.headless=true'

ExecStart=${tomcat_home}/bin/startup.sh
ExecStop=${tomcat_home}/bin/shutdown.sh

User=${sys_user}
Group=${sys_user}
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    echo_info ${tomcat_home} 目录授权
    chown -R ${sys_user}:${sys_user} ${tomcat_home}
    systemctl daemon-reload
    echo_info 启动tomcat
    systemctl start ${unit_file_name}
    if [ $? -ne 0 ];then
        echo_error tomcat启动失败，请检查
        exit 5
    fi
    echo_info tomcat已成功部署并启动，相关信息如下：
    echo -e "\033[37m                  启动命令：systemctl start ${unit_file_name}\033[0m"
    echo -e "\033[37m                  端口：${tomcat_http_port}\033[0m"
    echo -e "\033[37m                  部署目录：${tomcat_home}\033[0m"

}

function install_tomcat() {
    is_run_tomcat
    add_user_and_group ${sys_user}

    download_tar_gz ${src_dir} https://mirrors.cloud.tencent.com/apache/tomcat/tomcat-$(echo $tomcat_version | cut -d . -f 1)/v${tomcat_version}/bin/apache-tomcat-${tomcat_version}.tar.gz
    cd ${file_in_the_dir}
    untar_tgz apache-tomcat-${tomcat_version}.tar.gz
    mv apache-tomcat-${tomcat_version} ${tomcat_home}
    cd ${back_dir}
    echo_info 清理默认项目
    rm -rf ${tomcat_home}/webapps/*
    echo_info 调整tomcat配置
    sed -i 's/Connector port=\"8080\"/Connector port=\"'${tomcat_http_port}'\"/' ${tomcat_home}/conf/server.xml
    sed -i 's/Server port=\"8005\" shutdown="SHUTDOWN"/Server port="'${tomcat_shutdown_port}'" shutdown="SHUTDOWN"/' ${tomcat_home}/conf/server.xml

    generate_unit_file_and_start
}

install_tomcat