#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
my_dir=$(pwd)

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

#--------
function input_machine_ip_fun() {
    read input_machine_ip
    machine_ip=${input_machine_ip}
    if [[ ! $machine_ip =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
        echo_error 错误的ip格式，退出
        exit 7
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
#--------

function check_docker() {
    docker -v &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到docker，请先部署docker，参考部署脚本：
        echo https://github.com/zhegeshijiehuiyouai/RoadToDevOps/blob/master/01-installation-scripts/04-Docker/01-install-docker.sh
        exit 1
    fi
}

function docker_compose_start_apollo() {
    cd apollo
    echo_info 启动apollo
    docker-compose up -d
    get_machine_ip
    docker-compose ps -a
    echo_info 访问地址：http://${machine_ip}:8070
    echo -e "\033[37m                  账号：apollo\033[0m"
    echo -e "\033[37m                  密码：admin\033[0m"
    echo -e "\033[37m                  mysql用户名为root，密码为空\033[0m"
    exit 0
}

function install_by_docker() {
    if [ -d apollo ];then
        docker-compose ps -a | grep appolo &> /dev/null
        if [ $? -eq 0 ];then
            echo_info apollo已启动
            exit 0
        else
            docker_compose_start_apollo
        fi
    fi
    check_docker
    echo_info 下载apollo

    if [ -f apollo-master.zip ];then
        file_in_the_dir=$(pwd)
    elif [ -f ${src_dir}/apollo-master.zip ];then
        file_in_the_dir=${src_dir}
        cd ${file_in_the_dir}
    else
        download_tar_gz ${src_dir} https://github.com/ctripcorp/apollo/archive/refs/heads/master.zip
        if [ $? -ne 0 ];then
            echo_error 下载失败，可重试或手动下载压缩包放于当前目录，再运行本脚本
            echo https://github.com/ctripcorp/apollo/archive/refs/heads/master.zip
            exit 3
        fi
        cd ${file_in_the_dir}
        mv master.zip apollo-master.zip
    fi

    unzip -h &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装unzip
        yum install -y unzip
        if [ $? -ne 0 ];then
            echo_error unzip安装失败，请排查原因
            exit 2
        fi
    fi

    echo info 解压apollo压缩包
    unzip apollo-master.zip

    echo_info 提取docker-compose启动文件
    mv apollo-master/scripts/docker-quick-start ${my_dir}/apollo
    echo_info 清理临时文件
    rm -rf apollo-master

    docker_compose_start_apollo
}

function main() {
    install_by_docker
}

main
