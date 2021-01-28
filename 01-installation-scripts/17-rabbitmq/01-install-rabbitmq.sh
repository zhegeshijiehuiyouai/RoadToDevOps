#!/bin/bash

rabbitmq_ui_user=zhegeshijie
rabbitmq_ui_password=huiyouai
rabbitmq_ui_port=15672  # web服务的端口
rabbitmq_home=/data/rabbitmq
rabbitmq_port=5672  # client 端通信口


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

function is_installed_rabbitmq() {
    ps -ef | grep rabbitmq | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到本机上已部署 rabbitmq，退出
        exit 1
    fi
    if [ -d /etc/rabbitmq ];then
        echo_error 检测到 /etc/rabbitmq 目录，本机可能已部署了 rabbitmq，请退出检查
        exit 2
    fi
    if [ -d /var/lib/rabbitmq ];then
        echo_error 检测到 /var/lib/rabbitmq 目录，本机可能已部署了 rabbitmq，请退出检查
        exit 3
    fi
    if [ -d ${rabbitmq_home} ];then
        echo_error 检测到 ${rabbitmq_home} 目录，本机可能已部署了 rabbitmq，请退出检查
        exit 4
    fi
    if [ -f ~/.erlang.cookie ];then
        echo_error 检测到 ~/.erlang.cookie 文件，本机可能已部署了 rabbitmq，请退出检查
        exit 7
    fi
}

function config_rabbitmq() {
    # 如果已经部署了上面两个服务，但是吧配置文件删除了，进入下面的逻辑
    [ -d /etc/rabbitmq ] || mkdir -p /etc/rabbitmq

    mkdir -p ${rabbitmq_home}
    chown -R rabbitmq:rabbitmq ${rabbitmq_home}
    usermod -d ${rabbitmq_home} rabbitmq &> /dev/null

    sed -i 's#WorkingDirectory=/var/lib/rabbitmq#WorkingDirectory='${rabbitmq_home}'#g' /usr/lib/systemd/system/rabbitmq-server.service
    systemctl daemon-reload

    cat > /etc/rabbitmq/rabbitmq-env.conf <<EOF
RABBITMQ_MNESIA_BASE=${rabbitmq_home}/mnesia
RABBITMQ_LOG_BASE=${rabbitmq_home}/log
# 修改 .erlang.cookie 路径
HOME=${rabbitmq_home}
RABBITMQ_NODE_PORT=${rabbitmq_port}
# 集群端口
RABBITMQ_DIST_PORT=$(( ${rabbitmq_port} + 2000 ))
RABBITMQ_NODE_IP_ADDRESS=${machine_ip}
RABBITMQ_NODENAME=rabbit@$HOSTNAME
EOF
    cat > /etc/rabbitmq/rabbitmq.conf <<EOF
# 数据管理端口（默认端口为5672），这里的优先级比/etc/rabbitmq/rabbitmq-env.conf中的
# RABBITMQ_NODE_PORT优先级高，两个地方都写端口的话，这里的生效
# listeners.tcp.default=${rabbitmq_port}
# 界面管理端口（默认端口为15672）
management.tcp.port=${rabbitmq_ui_port}
management.tcp.ip=${machine_ip}
EOF
}

#-------------------------------------------------
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
#-------------------------------------------------

function install_by_rpm() {
    if [ ! -f /etc/yum.repos.d/rabbitmq_erlang.repo ];then
        echo_info 创建erlang.repo库
        curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | sudo bash
    fi
    if [ ! -f /usr/bin/erl ];then
        echo_info 安装erlang
        yum install -y erlang
        if [ $? -ne 0 ];then
            echo_error 安装 erlang 出错，退出
            exit 5
        fi
    fi
    
    if [ ! -f /etc/yum.repos.d/rabbitmq_rabbitmq-server.repo ];then
        echo_info 创建rabbitmq-server.repo库
        curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | sudo bash
    fi
    if [ ! -f /usr/sbin/rabbitmqctl ];then
        echo_info 安装rabbitmq-server
        yum install -y rabbitmq-server
        if [ $? -ne 0 ];then
            echo_error 安装 rabbitmq-server 出错，退出
            exit 6
        fi
    fi

    get_machine_ip

    echo_info 配置调整
    config_rabbitmq

    echo_info 启动rabbitmq服务
    systemctl start rabbitmq-server
    echo_info 启用管理后台
    rabbitmq-plugins enable rabbitmq_management
    echo_info 添加用户
    rabbitmqctl add_user ${rabbitmq_ui_user} ${rabbitmq_ui_password}
    echo_info 配置用户权限
    rabbitmqctl set_user_tags ${rabbitmq_ui_user} administrator
    rabbitmqctl  set_permissions -p "/" ${rabbitmq_ui_user} ".*" ".*" ".*"

    rm -rf /var/lib/rabbitmq

    echo_info RabbitMQ已部署，信息如下：
    echo -e "\033[37m                  启动命令：systemctl start rabbitmq-server\033[0m"
    echo -e "\033[37m                  epmd 停止命令：epmd -kill\033[0m"
    echo -e "\033[37m                  RabbitMQ 管理后台：http://${machine_ip}:${rabbitmq_ui_port}\033[0m"
    echo -e "\033[37m                  用户名：${rabbitmq_ui_user} 密码：${rabbitmq_ui_password}\033[0m"
}

function install_by_docker() {
    docker run -d -p 5672:5672 -p 15672:15672 --name rabbitmq rabbitmq:management
}


is_installed_rabbitmq
install_by_rpm
