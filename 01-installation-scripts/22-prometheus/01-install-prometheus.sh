#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
prometheus_port=9090
prometheus_version=2.27.1
# 部署prometheus的目录
prometheus_home=$(pwd)/prometheus-${prometheus_version}
sys_user=prometheus
unit_file_name=prometheus.service



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

function is_run_prometheus() {
    ps -ef | grep ${prometheus_home} | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到prometheus正在运行中，退出
        exit 3
    fi

    if [ -d ${prometheus_home} ];then
        echo_error 检测到目录${prometheus_home}，请检查是否重复安装，退出
        exit 4
    fi
}

function generate_unit_file_and_start() {
    get_machine_ip

    echo_info 生成${unit_file_name}文件用于systemd控制
    cat >/etc/systemd/system/${unit_file_name} <<EOF
[Unit]
Description=Prometheus -- script from https://github.com/zhegeshijiehuiyouai/RoadToDevOps
Documentation=https://prometheus.io/
After=network.target

[Service]
Type=simple
User=${sys_user}
Group=${sys_user}
ExecStart=${prometheus_home}/prometheus --config.file=${prometheus_home}/prometheus.yml --storage.tsdb.path=${prometheus_home}/data --web.console.libraries=${prometheus_home}/console_libraries --web.console.templates=${prometheus_home}/console --web.listen-address=:${prometheus_port} --web.external-url=http://${machine_ip}:${prometheus_port}/ 
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    echo_info ${prometheus_home} 目录授权
    chown -R ${sys_user}:${sys_user} ${prometheus_home}
    systemctl daemon-reload
    echo_info 启动prometheus
    systemctl start ${unit_file_name}
    if [ $? -ne 0 ];then
        echo_error prometheus启动失败，请检查
        exit 1
    fi
    systemctl enable ${unit_file_name} &> /dev/null

    echo_info prometheus已成功部署并启动，相关信息如下：
    echo -e "\033[37m                  启动命令：systemctl start ${unit_file_name}\033[0m"
    echo -e "\033[37m                  端口：${prometheus_port}\033[0m"
    echo -e "\033[37m                  部署目录：${prometheus_home}\033[0m"
    echo -e "\033[37m                  prometheus访问地址：http://${machine_ip}:${prometheus_port}/\033[0m"
}

function download_and_config() {
    download_tar_gz ${src_dir} https://github.com/prometheus/prometheus/releases/download/v${prometheus_version}/prometheus-${prometheus_version}.linux-amd64.tar.gz
    cd ${file_in_the_dir}
    untar_tgz prometheus-${prometheus_version}.linux-amd64.tar.gz
    mv prometheus-${prometheus_version}.linux-amd64 ${prometheus_home}
    mkdir -p ${prometheus_home}/{data,rules}

    sed -i 's/localhost:9090/localhost:'${prometheus_port}'/' ${prometheus_home}/prometheus.yml

    add_user_and_group ${sys_user}
    generate_unit_file_and_start
}

function install_prometheus() {
    is_run_prometheus
    download_and_config
}

install_prometheus