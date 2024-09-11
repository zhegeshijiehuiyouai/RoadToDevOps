#!/bin/bash

#################################配置
# 目录配置
src_dir=$(pwd)/00src00
# rocketmq家目录的父目录，在父目录下创建rocketmq-${version}目录作为应用目录
rocketmq_father_home=$(pwd)
# rockermq版本
rocketmq_version_4x=4.9.8
rocketmq_version_5x=5.3.0
# 以什么用户启动rockermq
sys_user=rocketmq

#### 端口配置
nameserver_port=9876
# broker对外服务的监听端口
broker_listen_port=10911
# 主要用于slave同步master，默认为broker_listen_port - 2
broker_fast_listen_port=10909
# HAService组件服务使用，默认为broker_listen_port + 1
broker_ha_listen_port=10912
#  proxy代理监听端口
proxy_remoting_listen_port=9080
# proxy gRPC服务器端口
proxy_grpc_server_port=9081

# nameserver运行内存配置
nameserver_java_xms=512m
nameserver_java_xmx=512m
nameserver_java_xmn=256m
# broker运行内存配置
broker_java_xms=512m
broker_java_xmx=512m
broker_java_xmn=256m
# broker集群名字
broker_cluster_name=DefaultCluster
# unit file文件名
unit_file_name_nameserver=rmq_namesrv.service
unit_file_name_broker=rmq_broker.service
unit_file_name_proxy=rmq_proxy.service
#################################

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

# 脚本执行用户检测
if [[ $(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

# 检测操作系统
if [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)
elif [[ -e /etc/almalinux-release ]]; then
    os="alma"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/almalinux-release)
else
	echo_error 不支持的操作系统
	exit 99
fi

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
                if [[ $os == "centos" ]];then
                    yum install -y wget
                elif [[ $os == "ubuntu" ]];then
                    apt install -y wget
                elif [[ $os == "rocky" || $os == "alma" ]];then
                    dnf install -y wget
                fi
            fi
            wget $2
            if [ $? -ne 0 ];then
                echo_error 下载 $2 失败！
                exit 80
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
                    if [[ $os == "centos" ]];then
                        yum install -y wget
                    elif [[ $os == "ubuntu" ]];then
                        apt install -y wget
                    elif [[ $os == "rocky" || $os == "alma" ]];then
                        dnf install -y wget
                    fi
                fi
                wget $2
                if [ $? -ne 0 ];then
                    echo_error 下载 $2 失败！
                    exit 80
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

function choose_dir_action() {
    read -p "请输入（如需退出请输入q）：" -e user_choose_dir_action
    case $user_choose_dir_action in
        1)
            echo_info 用户主动退出
            exit 0
            ;;
        2)
            echo_info 删除目录 ${rocketmq_home}
            rm -rf ${rocketmq_home}
            ;;
        3)
            echo_info 保留目录 ${rocketmq_home}
            true
            ;;
        q|Q)
            exit 0
            ;;
        *)
            echo_warning 请输入对应序号
            choose_dir_action
            ;;
    esac
}

function is_run_rocketmq() {
    if [[ $rocketmq_version == $rocketmq_version_4x ]];then
        ps -ef | grep ${rocketmq_home}/ | grep -v grep &> /dev/null
        if [ $? -eq 0 ];then
            echo_error 检测到rocketmq正在运行中，退出
            exit 3
        fi

        if [ -d ${rocketmq_home} ];then
            echo_error 检测到目录${rocketmq_home}，请检查是否重复安装，退出
            exit 4
        fi
    elif [[ $rocketmq_version == $rocketmq_version_5x ]];then
        if [ -d ${rocketmq_home} ];then
            echo_warning 检测到目录${rocketmq_home}，请输入序号选择操作
            echo -e "\033[36m[1]\033[32m 重复部署了，退出\033[0m"
            echo -e "\033[36m[2]\033[32m 准备重新部署，删除目录，继续下一步\033[0m"
            echo -e "\033[36m[3]\033[32m 部署组件，保留目录，继续下一步\033[0m"
            choose_dir_action
        fi
    fi
}

function check_jdk() {
    java -version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到jdk，请先部署jdk
        exit 1
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

function generate_nameserver_unit_file() {
    echo_info 生成${unit_file_name_nameserver}文件用于systemd控制
    cat >/etc/systemd/system/${unit_file_name_nameserver} <<EOF
[Unit]
Description=rocketmq nameserver
After=network.target

[Service]
#这里Type一定要写simple
Type=simple

ExecStart=${rocketmq_home}/bin/mqnamesrv -c ${rocketmq_home}/conf/namesrv.properties
ExecStop=${rocketmq_home}/bin/mqshutdown namesrv
User=rocketmq
Group=rocketmq

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo_info nameserver已部署完毕，相关信息如下：
    echo -e "\033[37m                  nameserver端口：${nameserver_port}\033[0m"
    echo -e "\033[37m                  nameserver启动：systemctl start ${unit_file_name_nameserver}\033[0m"
}

function generate_broker_unit_file() {
    if [[ -z ${broker_config_file} ]]; then
        broker_config_file=broker-a.properties
    fi
    echo_info 生成${unit_file_name_broker}文件用于systemd控制
    cat >/etc/systemd/system/${unit_file_name_broker} <<EOF
[Unit]
Description=rocketmq borker
After=network.target

[Service]
Type=simple
# 如要配置多主多从，则将配置文件替换为${rocketmq_home}/conf/{2m-2s-async  2m-2s-sync  2m-noslave}下的配置文件
# ExecStart=${rocketmq_home}/bin/mqbroker -c ${rocketmq_home}/conf/broker.conf
ExecStart=${rocketmq_home}/bin/mqbroker -c ${rocketmq_home}/conf/2m-2s-async/${broker_config_file}
ExecStop=/usr/local/rocketmq/bin/mqshutdown broker
User=rocketmq
Group=rocketmq

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo_info broker已部署完毕，相关信息如下：
    echo -e "\033[37m                  broker端口：${broker_listen_port}\033[0m"
    echo -e "\033[37m                  broker启动：systemctl start ${unit_file_name_broker}\033[0m"
}

function generate_proxy_unit_file() {
    cat >/etc/systemd/system/${unit_file_name_proxy} <<EOF
[Unit]
Description=rocketmq proxy
After=network.target

[Service]
Type=simple
ExecStart=${rocketmq_home}/bin/mqproxy -pc ${rocketmq_home}/conf/rmq-proxy.json
ExecStop=/usr/local/rocketmq/bin/mqshutdown proxy
User=rocketmq
Group=rocketmq

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    echo_info proxy已部署完毕，相关信息如下：
    echo -e "\033[37m                  proxy端口：${proxy_remoting_listen_port}\033[0m"
    echo -e "\033[37m                  proxy启动：systemctl start ${unit_file_name_proxy}\033[0m"
}

function common_action_1() {
    get_machine_ip
    unar -v &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装解压工具
        if [[ $os == "centos" ]];then
            yum install -y epel-release
            yum install -y unar
            if [ $? -ne 0 ];then
                echo_error unar安装失败，请检查网络
                exit 1
            fi
        elif [[ $os == "rocky" || $os == "alma" ]];then
            dnf install -y unar
            if [ $? -ne 0 ];then
                echo_error unar安装失败，请检查网络
                exit 1
            fi
        fi
    fi

    # 如果是部署组件，要保留目录，那么就不执行下面的内容
    if [[ $user_choose_dir_action != 3 ]];then
        download_tar_gz ${src_dir} https://dist.apache.org/repos/dist/release/rocketmq/${rocketmq_version}/rocketmq-all-${rocketmq_version}-bin-release.zip
        cd ${file_in_the_dir}
        unar rocketmq-all-${rocketmq_version}-bin-release.zip
        mv rocketmq-all-${rocketmq_version}-bin-release ${rocketmq_home}
        add_user_and_group ${sys_user}
        echo_info 修改rocketmq日志目录
        cd ${rocketmq_home}
        mkdir -p {logs,store/{commitlog,consumequeue}}
        sed -i 's#\${user.home}#'${rocketmq_home}'#g' ${rocketmq_home}/conf/*.xml
    fi
}

function config_nameserver() {
    cd ${rocketmq_home}
    echo_info 修改nameserver初始化堆栈大小
    sed -i -E 's/(-Xms)[^ ]*/\1'${nameserver_java_xms}'/' ${rocketmq_home}/bin/runserver.sh
    sed -i -E 's/(-Xmx)[^ ]*/\1'${nameserver_java_xmx}'/' ${rocketmq_home}/bin/runserver.sh
    # 先删除原有的 -Xmn 参数
    sed -i -E 's/-Xmn[^ ]*\s*//g' ${rocketmq_home}/bin/runserver.sh
    # 再添加新的 -Xmn 参数
    sed -i -E "s/(-Xmx[^ ]*)/\1 -Xmn${nameserver_java_xmn}/" ${rocketmq_home}/bin/runserver.sh
    echo_info 生成nameserver配置文件
    cat > ${rocketmq_home}/conf/namesrv.properties << EOF
listenPort=${nameserver_port}
EOF
    chown -R ${sys_user}:${sys_user} ${rocketmq_home}
    generate_nameserver_unit_file
}

function choose_nameserver_addr(){
    read -p "请输入（如需退出请输入q）：" -e user_choose_nameserver_addr
    case $user_choose_nameserver_addr in
        1)
            nameserver_addr=${machine_ip}:${nameserver_port}
            ;;
        2)
            read -p "请输入nameserver地址(ip:port)，多个地址使用英文分号分隔：" -e nameserver_addr
            ;;
        q|Q)
            exit 0
            ;;
        *)
            echo_warning 请输入对应序号
            choose_nameserver_addr
            ;;
    esac
}

function generate_broker_config() {
    broker_config_file=${1}.properties
    if [[ $1 == "broker-a" ]];then
        broker_name="broker-a"
        broker_id="0"
        broker_role="ASYNC_MASTER"
    elif [[ $1 == "broker-a-s" ]];then
        broker_name="broker-a"
        broker_id="2"
        broker_role="SLAVE"
    elif [[ $1 == "broker-b" ]];then
        broker_name="broker-b"
        broker_id="0"
        broker_role="ASYNC_MASTER"
    elif [[ $1 == "broker-b-s" ]];then
        broker_name="broker-b"
        broker_id="2"
        broker_role="SLAVE"
    fi

    if [[ ${user_choose_install_5x_component} == 2 ]];then
        is_enable_proxy="true"
    elif [[ ${user_choose_install_5x_component} == 3 ]];then
        is_enable_proxy="false"
    fi

    echo_warning 是否使用 ${machine_ip}:${nameserver_port} 作为nameserver地址？
    echo -e "\033[36m[1]\033[32m 是\033[0m"
    echo -e "\033[36m[2]\033[32m 否，手动输入nameserver地址\033[0m"
    choose_nameserver_addr

    cat > ${rocketmq_home}/conf/2m-2s-async/${broker_config_file} << EOF
# 所属集群的名字
brokerClusterName=${broker_cluster_name}
# Broker的名称
brokerName=${broker_name}
# brokerId为0表示Master，>0表示Slave。配置slave的话记得下面的brokerRole参数修改为brokerRole=SLAVE
brokerId=${broker_id}
# Broker对外服务的监听端口
listenPort=${broker_listen_port}
# 主要用于slave同步master，默认为broker_listen_port - 2
fastListenPort=${broker_fast_listen_port}
# HAService组件服务使用，默认为broker_listen_port + 1
haListenPort=${broker_ha_listen_port}
# NameServer地址，使用分号分隔
# namesrvAddr=ip1:port1;ip2:port2
namesrvAddr=${nameserver_addr}
# 删除文件时间点, 默认为凌晨4点
deleteWhen=04
# 文件保留时间, 默认48小时
fileReservedTime=72
# Broker Role
brokerRole=${broker_role}
# 开启从Slave读数据功能
# slaveReadEnable=true
# 刷盘方式，ASYNC_FLUSH：异步刷盘
flushDiskType=ASYNC_FLUSH
# 存储路径
storePathRootDir=${rocketmq_home}/store
# commitLog存储路径
storePathCommitLog=${rocketmq_home}/store/commitlog
# 消费队列存储路径
storePathConsumeQueue=${rocketmq_home}/store/consumequeue
# 消息索引存储路径
storePathIndex=${rocketmq_home}/store/index
# checkpoint 文件存储路径
storeCheckpoint=${rocketmq_home}/store/checkpoint
# abort 文件存储路径
abortFile=${rocketmq_home}/store/abort
# 是否允许Broker自动创建Topic
autoCreateTopicEnable=true
# 是否允许Broker自动创建订阅组
autoCreateSubscriptionGroup=true
#commitLog每个文件的大小，默认是1G
mapedFileSizeCommitLog=1073741824
#ConsumerQueue每个文件默认存30W条
mapedFileSizeConsumeQueue=300000
#限制的消息大小
maxMessageSize=65536
#强制指定本机IP，需要根据每台机器进行修改。官方介绍可为空，系统默认自动识别，但多网卡时IP地址可能读取错误
brokerIP1=${machine_ip}
# Proxy 和 Broker 是否同进程部署
enableProxy=${is_enable_proxy}
EOF

    chown -R ${sys_user}:${sys_user} ${rocketmq_home}
    generate_broker_unit_file
}


function choose_2m_2s_config_implement() {
    read -p "请输入（如需退出请输入q）：" -e user_choose_2m_2s_config_implement
    case $user_choose_2m_2s_config_implement in
        1)
            echo_info 配置为 A-Master
            generate_broker_config broker-a
            ;;
        2)
            echo_info 配置为 A-Slave
            generate_broker_config broker-a-s
            ;;
        3)
            echo_info 配置为 B-Master
            generate_broker_config broker-b
            ;;
        4)
            echo_info 配置为 B-Slave
            generate_broker_config broker-b-s
            ;;
        q|Q)
            exit 0
            ;;
        *)
            echo_warning 请输入对应序号
            choose_2m_2s_config_implement
            ;;
    esac
}

function choose_2m_2s_config() {
    echo_info 优化broker配置文件,多节点（集群）多副本模式-异步复制 2m-2s-async
    echo -e "\033[31m请输入序号选择 当前节点角色\033[0m"
    echo -e "\033[36m[1]\033[32m A-Master\033[0m"
    echo -e "\033[36m[2]\033[32m A-Slave\033[0m"
    echo -e "\033[36m[3]\033[32m B-Master\033[0m"
    echo -e "\033[36m[4]\033[32m B-Slave\033[0m"
    choose_2m_2s_config_implement
}

function config_broker_proxy() {
    cd ${rocketmq_home}
    # 提取java主版本号
    java_major_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | awk -F. '{print $1}')
    if [ ${java_major_version} -ge 15 ]; then
        echo_info 'java版本大于等于15，删除 -XX:-UseBiasedLocking'
        sed -i 's/ -XX:-UseBiasedLocking//g' ${rocketmq_home}/bin/runbroker.sh
    fi
    echo_info 修改broker初始化堆栈大小
    sed -i 's#JAVA_OPT="${JAVA_OPT} -server -Xms.*#JAVA_OPT="${JAVA_OPT} -server -Xms'${broker_java_xms}' -Xmx'${broker_java_xmx}' -Xmn'${broker_java_xmn}'"#g' ${rocketmq_home}/bin/runbroker.sh
    choose_2m_2s_config
}

function config_proxy() {
    echo_info 配置rmq-proxy.json
    echo_warning 是否使用 ${machine_ip}:${nameserver_port} 作为nameserver地址？
    echo -e "\033[36m[1]\033[32m 是\033[0m"
    echo -e "\033[36m[2]\033[32m 否，手动输入nameserver地址\033[0m"
    choose_nameserver_addr
    cat > ${rocketmq_home}/conf/rmq-proxy.json << EOF
{
    //集群名称 与broker一致
    "rocketMQClusterName": "${broker_cluster_name}",
    // 代理监听端口
    "remotingListenPort": ${proxy_remoting_listen_port},
    // gRPC服务器端口
    "grpcServerPort": ${proxy_grpc_server_port},
    // 对应namesr的ip
    "namesrvAddr": "${nameserver_addr}"
}
EOF

    chown -R ${sys_user}:${sys_user} ${rocketmq_home}
    generate_proxy_unit_file
}

function binary_install_4x() {
    # 5.x中，打算拆分服务，各个服务可以单独安装，所以判断rocketmq是否启动，就不放在common_pre_install_check里
    is_run_rocketmq
    common_action_1

    echo_info 修改nameserver初始化堆栈大小
    sed -i -E 's/(-Xms)[^ ]*/\1'${nameserver_java_xms}'/' ${rocketmq_home}/bin/runserver.sh
    sed -i -E 's/(-Xmx)[^ ]*/\1'${nameserver_java_xmx}'/' ${rocketmq_home}/bin/runserver.sh
    # 先删除原有的 -Xmn 参数
    sed -i -E 's/-Xmn[^ ]*\s*//g' ${rocketmq_home}/bin/runserver.sh
    # 再添加新的 -Xmn 参数
    sed -i -E "s/(-Xmx[^ ]*)/\1 -Xmn${nameserver_java_xmn}/" ${rocketmq_home}/bin/runserver.sh
    echo_info 修改broker初始化堆栈大小
    sed -i 's#JAVA_OPT="${JAVA_OPT} -server -Xms.*#JAVA_OPT="${JAVA_OPT} -server -Xms'${broker_java_xms}' -Xmx'${broker_java_xmx}' -Xmn'${broker_java_xmn}'"#g' ${rocketmq_home}/bin/runbroker.sh

    echo_info 生成nameserver配置文件
    cat > ${rocketmq_home}/conf/namesrv.properties << EOF
listenPort=${nameserver_port}
EOF

    echo_info 优化broker配置文件,多节点（集群）多副本模式-异步复制 2m-2s-async
    cat > ${rocketmq_home}/conf/2m-2s-async/broker-a.properties << EOF
# 所属集群的名字
brokerClusterName=my-rocketmq-cluster
# Broker的名称
brokerName=broker-a
# brokerId为0表示Master，>0表示Slave。配置slave的话记得下面的brokerRole参数修改为brokerRole=SLAVE
brokerId=0
# Broker对外服务的监听端口
listenPort=${broker_listen_port}
# NameServer地址，使用分号分隔
# namesrvAddr=${machine_ip}:${nameserver_port};nameserver_2_ip:nameserver_2_port
namesrvAddr=${machine_ip}:${nameserver_port}
# 删除文件时间点, 默认为凌晨4点
deleteWhen=04
# 文件保留时间, 默认48小时
fileReservedTime=72
# Broker Role
brokerRole=ASYNC_MASTER
# 开启从Slave读数据功能
# slaveReadEnable=true
# 刷盘方式，ASYNC_FLUSH：异步刷盘
flushDiskType=ASYNC_FLUSH
# 存储路径
storePathRootDir=${rocketmq_home}/store
# commitLog存储路径
storePathCommitLog=${rocketmq_home}/store/commitlog
# 消费队列存储路径
storePathConsumeQueue=${rocketmq_home}/store/consumequeue
# 消息索引存储路径
storePathIndex=${rocketmq_home}/store/index
# checkpoint 文件存储路径
storeCheckpoint=${rocketmq_home}/store/checkpoint
# abort 文件存储路径
abortFile=${rocketmq_home}/store/abort
# 是否允许Broker自动创建Topic
autoCreateTopicEnable=true
# 是否允许Broker自动创建订阅组
autoCreateSubscriptionGroup=true
#commitLog每个文件的大小，默认是1G
mapedFileSizeCommitLog=1073741824
#ConsumerQueue每个文件默认存30W条
mapedFileSizeConsumeQueue=300000
#限制的消息大小
maxMessageSize=65536
#强制指定本机IP，需要根据每台机器进行修改。官方介绍可为空，系统默认自动识别，但多网卡时IP地址可能读取错误
brokerIP1=${machine_ip}
EOF

    chown -R ${sys_user}:${sys_user} ${rocketmq_home}

    generate_nameserver_unit_file
    generate_broker_unit_file
}

function binary_install_5x_nameserver() {
    is_run_rocketmq
    common_action_1
    config_nameserver
}

function binary_install_5x_broker_proxy() {
    is_run_rocketmq
    common_action_1
    config_broker_proxy
}

function binary_install_5x_proxy() {
    is_run_rocketmq
    common_action_1
    config_proxy
}


function choose_install_5x_component(){
    read -p "请输入（如需退出请输入q）：" -e user_choose_install_5x_component
    case $user_choose_install_5x_component in
        1)
            echo_info 选择了部署 NameServer
            binary_install_5x_nameserver
            ;;
        2)
            echo_info 选择了部署 Broker+Proxy（同进程部署）
            binary_install_5x_broker_proxy
            ;;
        3)
            echo_info 选择了部署 Broker
            # 通过变量user_choose_install_5x_component来和上面做区分
            binary_install_5x_broker_proxy
            ;;
        4)
            echo_info 选择了部署 Proxy
            binary_install_5x_proxy
            ;;
        q|Q)
            exit 0
            ;;
        *)
            echo_warning 请输入对应序号
            choose_install_5x_component
            ;;
    esac
}

function binary_install_5x() {
    echo -e "\033[31m请输入序号选择要部署的服务\033[0m"
    echo -e "\033[36m[1]\033[32m NameServer\033[0m"
    echo -e "\033[36m[2]\033[32m Broker+Proxy（同进程部署）\033[0m"
    echo -e "\033[36m[3]\033[32m Broker\033[0m"
    echo -e "\033[36m[4]\033[32m Proxy\033[0m"
    choose_install_5x_component
}

function choose_rocketmq_version(){
    read -p "请输入（如需退出请输入q）：" -e user_choose_rocketmq_version
    case $user_choose_rocketmq_version in
        1)
            rocketmq_version=${rocketmq_version_4x}
            rocketmq_home=${rocketmq_father_home}/rocketmq-${rocketmq_version}
            echo_info 选择了部署 RocketMQ ${rocketmq_version}
            binary_install_4x
            ;;
        2)
            rocketmq_version=${rocketmq_version_5x}
            rocketmq_home=${rocketmq_father_home}/rocketmq-${rocketmq_version}
            echo_info 选择了部署 RocketMQ ${rocketmq_version}
            binary_install_5x
            ;;
        q|Q)
            exit 0
            ;;
        *)
            choose_rocketmq_version
            ;;
    esac
}

function main(){
    check_jdk
    echo -e "\033[31m本脚本支持两种版本的RocketMQ，请输入序号选择要部署的版本\033[0m"
    echo -e "\033[36m[1]\033[32m ${rocketmq_version_4x}\033[0m"
    echo -e "\033[36m[2]\033[32m ${rocketmq_version_5x}\033[0m"
    choose_rocketmq_version
}

main