#!/bin/bash

web_port=80
ssh_port=2222

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

# jumpserver_data_dir=/data/jumpserver/data
# jumpserver_mysql_dir=/data/jumpserver/mysql
# [ -d $jumpserver_data_dir ] || mkdir -p $jumpserver_data_dir
# [ -d $jumpserver_mysql_dir ] || mkdir -p $jumpserver_mysql_dir

source ~/.bashrc
echo_info 准备生成key和token
grep SECRET_KEY ~/.bashrc &> /dev/null
if [ $? -ne 0 ]; then
    SECRET_KEY=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 50`
    echo "SECRET_KEY=$SECRET_KEY" >> ~/.bashrc
    echo $SECRET_KEY
else
    echo_warning SECRET_KEY已存在：${SECRET_KEY}
fi
grep BOOTSTRAP_TOKEN ~/.bashrc &> /dev/null
if [ $? -ne 0 ]; then
    BOOTSTRAP_TOKEN=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 16`
    echo "BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN" >> ~/.bashrc
    echo $BOOTSTRAP_TOKEN
else
    echo_warning BOOTSTRAP_TOKEN已存在：${BOOTSTRAP_TOKEN}
fi

# docker启动命令
echo_info 通过docker启动容器，容器名为jms_all
    #    -v ${jumpserver_data_dir}:/opt/jumpserver/data \
    #    -v ${jumpserver_mysql_dir}:/var/lib/mysql \
docker run --name jms_all -d \
       -p ${web_port}:80 \
       -p ${ssh_port}:2222 \
       -e SECRET_KEY=$SECRET_KEY \
       -e BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN \
       --restart=always \
       jumpserver/jms_all

if [ $? -ne 0 ];then
    exit 1
fi

echo_info jumpserver已启动成功，以下是相关信息：
echo -e "\033[37m                  端口：${web_port}\033[0m"
# echo -e "\033[37m                  存放key和token的文件：~/.bashrc ，不要修改文件中的 SECRET_KEY 和 BOOTSTRAP_TOKEN ，这样重新运行该脚本，新生成的jumpserver容器就可以获取之前的配置\033[0m"
# echo -e "\033[37m                  jumpserver数据目录：$(dirname ${jumpserver_data_dir})/ ，不要删除该目录，这样重新运行该脚本，新生成的jumpserver容器就可以获取之前的配置和数据\033[0m"
