#!/bin/bash

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

SRC_DIR=$(pwd)/00src00
MY_DIR=$(pwd)
JUMP_HOME=jumpserver
JUMP_GIT_DIR=Dockerfile
JUMP_PORT=11880


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

function pre_check() {
    if [ -d ${JUMP_HOME} ];then
        echo_error 检测到${JUMP_HOME}目录，请确认是否重复安装
        exit 1
    fi

    if [ -f ${SRC_DIR}/master.zip ];then
        echo_error 检测到${SRC_DIR}/master.zip文件，请确认是否重复安装
        exit 2
    fi

    unzip -h &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装unzip
        yum install -y unzip
        if [ $? -ne 0 ];then
            echo_error 安装unzip失败，退出
            exit 3
        fi
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

function download_and_startup_jumpserver() {
    download_tar_gz ${SRC_DIR} https://github.com/jumpserver/Dockerfile/archive/refs/heads/master.zip
    cd ${SRC_DIR}
    echo_info 解压master.zip
    unzip master.zip

    mv ${JUMP_GIT_DIR}-master ${MY_DIR}/${JUMP_HOME}
    rm -f master.zip
    cd ${MY_DIR}/${JUMP_HOME}
    cp config_example.conf .env

    echo_info 调整jumpserver配置
    sed -i "s#80:80#${JUMP_PORT}:80#g" docker-compose.yml

    echo_info 如有更多修改，请编辑 ${JUMP_HOME}/.env 文件

    echo_info 启动jumpserver
    docker-compose up -d
    if [ $? -ne 0 ];then
        echo_error 哦豁，启动报错了，请检查docker-compose.yml文件
        exit 4
    fi
    get_machine_ip
    echo_info jumpserver已部署成功，访问地址：http://${machine_ip}:${JUMP_PORT}
    echo -e "\033[37m                  默认账号：admin\033[0m"
    echo -e "\033[37m                  默认密码：admin\033[0m"
}

pre_check
download_and_startup_jumpserver
