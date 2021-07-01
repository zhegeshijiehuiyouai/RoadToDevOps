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

function check_git() {
    git --version &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装git
        yum install -y git
    fi
}

function check_docker() {
    docker -v &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到docker，请先部署docker，参考部署脚本：
        echo https://github.com/zhegeshijiehuiyouai/RoadToDevOps/blob/master/01-installation-scripts/04-Docker/01-install-docker.sh
        exit 1
    fi
}

function docker_compose_start_nacos() {
    cd nacos-docker
    echo_info 启动nacos，命令：docker-compose -f example/standalone-mysql-5.7.yaml up -d
    docker-compose -f example/standalone-mysql-5.7.yaml up -d
    get_machine_ip
    echo_info 访问地址：http://${machine_ip}:8848/nacos
    echo -e "\033[37m                  账号：nacos\033[0m"
    echo -e "\033[37m                  密码：nacos\033[0m"
    exit 0
}

function install_by_docker() {
    if [ -d nacos-docker ];then
        docker-compose -f nacos-docker/example/standalone-mysql-5.7.yaml ps -a | grep nacos &> /dev/null
        if [ $? -eq 0 ];then
            echo_info nacos已启动
            exit 0
        else
            docker_compose_start_nacos
        fi
    fi
    check_docker
    echo_info 下载nacos docker项目
    git clone https://github.com/nacos-group/nacos-docker.git
    if [ $? -ne 0 ];then
        echo_error 下载失败，可重试或手动下载，解压后重命名为nacos-docker，再运行本脚本
        echo https://github.com/nacos-group/nacos-docker/archive/refs/heads/master.zip
        exit 3
    fi
    docker_compose_start_nacos
}

function main() {
    check_git
    install_by_docker
}

main
