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

function show_summary() {
    echo_info 配置文件 ：zkui/config.cfg
    echo -e "\033[37m                  主要配置项：\033[0m"
    echo -e "\033[37m                      serverPort -- zkui监听的端口\033[0m"
    echo -e "\033[37m                      zkServer   -- 管理的zk，zk集群可以用逗号隔开\033[0m"
    echo -e "\033[37m                      userSet    -- zkui的用户设置，role可以设置为ADMIN、USER，ADMIN有增删改的权限，USER只可以查看\033[0m"
    echo -e "\033[37m                  启动命令 ：cd zkui; nohup java -jar target/zkui-2.0-SNAPSHOT-jar-with-dependencies.jar &>/dev/null &\033[0m"
    echo
}

java -version &> /dev/null
if [ $? -ne 0 ];then
    echo_error 未检测到jdk，请先部署jdk
    exit 1
fi

mvn -version &> /dev/null
if [ $? -ne 0 ];then
    echo_error 未检测到maven，请先部署maven
    exit 2
fi

git --version &> /dev/null
if [ $? -ne 0 ];then
    echo_info 安装git中
    yum install -y git
fi

if [ ! -d zkui ];then
    echo_info 从github下载zkui，项目地址：https://github.com/DeemOpen/zkui.git
    git clone https://github.com/DeemOpen/zkui.git
else
    echo_info 发现zkui目录
fi

cd zkui

if [ -f target/zkui-2.0-SNAPSHOT-jar-with-dependencies.jar ];then
    echo_info 检测到zkui jar包，可直接启动
    show_summary
else
    echo_info 打包中
    mvn clean install
    if [ $? -eq 0 ];then
        show_summary
    else
        echo_error 打包出错，请检查
        exit 3
    fi
fi
