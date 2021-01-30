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
        exit 8
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

function is_run_docker_rabbitmq() {
    docker version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 您尚未安装 docker，退出
        exit 9
    fi
    docker ps -a | awk '{print $NF}' | grep rabbitmq &>/dev/null
    if [ $? -eq 0 ];then
        echo_error 已存在 rabbitmq 容器，退出
        exit 10
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
    get_machine_ip

    container_name=rabbitmq
    echo -e -n "容器id  ："
    docker run -d --hostname ${container_name} \
               --name ${container_name} \
               -e RABBITMQ_DEFAULT_USER=${rabbitmq_ui_user} \
               -e RABBITMQ_DEFAULT_PASS=${rabbitmq_ui_password} \
               -v ${rabbitmq_home}:/var/lib/rabbitmq \
               -p ${rabbitmq_ui_port}:15672 \
               -p ${rabbitmq_port}:5672 \
               rabbitmq:management
    echo 容器name：${container_name}

    echo_info RabbitMQ已部署，信息如下：
    echo -e "\033[37m                  启动命令：docker start rabbitmq\033[0m"
    echo -e "\033[37m                  RabbitMQ 管理后台：http://${machine_ip}:${rabbitmq_ui_port}\033[0m"
    # 如果存在数据目录，那么启动命令中设置的账号密码可能失效
    if [ -d ${rabbitmq_home} ];then
        echo -e "\033[1;31m                  由于存在挂载目录 ${rabbitmq_home}，用户名：${rabbitmq_ui_user} 密码：${rabbitmq_ui_password} 可能不正确！\033[0m"
        echo -e "\033[1;31m                  请以之前部署的 rabbitmq 账号密码为准\033[0m"
    else
        echo -e "\033[37m                  用户名：${rabbitmq_ui_user} 密码：${rabbitmq_ui_password}\033[0m"
    fi
}

function install_main_func(){
    read -p "请输入数字选择安装类型（如需退出请输入q）：" software
    case $software in
        1)
            # 安装前先判断是否已经安装了rabbitmq
            is_installed_rabbitmq
            echo_info 即将使用 yum 安装rabbitmq
            # 等待1秒，给用户手动取消的时间
            sleep 1
            install_by_rpm
            ;;
        2)
            is_run_docker_rabbitmq
            echo_info 即将使用 docker 安装rabbitmq
            sleep 1
            install_by_docker
            ;;
        q|Q)
            exit 0
            ;;
        *)
            install_main_func
            ;;
    esac
}

echo -e "\033[31m本脚本支持两种部署方式：\033[0m"
echo -e "\033[36m[1]\033[32m yum安装rabbitmq\033[0m"
echo -e "\033[36m[2]\033[32m docker安装rabbitmq\033[0m"
install_main_func