#!/bin/bash

# 目录配置
src_dir=$(pwd)/00src00
rocketmq_console_home=$(pwd)/rocketmq_console

function check_java_and_maven() {
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
}

check_java_and_maven