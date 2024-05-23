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

print_help() {
    echo "使用方法: $0 容器Name/ID"
}

# 脚本执行用户检测
if [[ $(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

# 检查是否传入参数
if [ $# -eq 0 ]; then
    echo_error "错误: 没有传入参数。"
    print_help
    exit 1
fi

# 检查参数是否正确
if [ $# -gt 1 ]; then
    echo_error "错误: 只能传一个参数。"
    print_help
    exit 1
fi

# 检查容器是否正常运行
docker ps -a | grep $1 &> /dev/null
if [ $? -ne 0 ];then
    echo_error "未找到容器：$1"
    exit 2
fi

docker ps -a | grep $1 | grep "Exited" &> /dev/null
if [ $? -eq 0 ];then
    echo_error "容器 $1 已退出"
    exit 2
fi

# 检查nsenter命令
command -v nsenter &> /dev/null
if [ $? -ne 0 ];then
    echo_info 安装nsenter
    yum install -y util-linux
fi

container_pid=$(docker inspect -f {{.State.Pid}} $1)
nsenter -n -t $container_pid ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1
