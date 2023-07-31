#!/bin/bash

# 目录配置
src_dir=$(pwd)/00src00
rocketmq_home=$(pwd)/rocketmq
# rockermq版本
rocketmq_version=4.9.1
# 以什么用户启动rockermq
sys_user=rocketmq
# 端口配置
nameserver_port=9876
broker_port=10911
# 使用域名访问服务
nameserver_dns_name=rocketmq-nameserver-1
# broker运行内存配置
broker_java_xms=512m
broker_java_xmx=512m
broker_java_xmn=256m
# unit file文件名
unit_file_name_nameserver=rmq_namesrv.service
unit_file_name_broker=rmq_broker.service

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
    if [ $http_code -ne 200 ];then
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
                yum install -y wget
            fi
            wget $2
            if [ $? -ne 0 ];then
                echo_error 下载 $2 失败！
                exit 1
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
                    yum install -y wget
                fi
                wget $2
                if [ $? -ne 0 ];then
                    echo_error 下载 $2 失败！
                    exit 1
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

function is_run_rocketmq() {
    ps -ef | grep ${rocketmq_home}/ | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到rocketmq正在运行中，退出
        exit 3
    fi

    if [ -d ${rocketmq_home} ];then
        echo_error 检测到目录${rocketmq_home}，请检查是否重复安装，退出
        exit 4
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

function generate_unit_file() {
    echo_info 生成${unit_file_name_nameserver}文件用于systemd控制
    cat >/usr/lib/systemd/system/${unit_file_name_nameserver} <<EOF
[Unit]
Description=rocketmq nameserver
After=network.target

[Service]
#这里Type一定要写simple
Type=simple

#ExecStart和ExecStop分别在systemctl start和systemctl stop时候调动
ExecStart=${rocketmq_home}/bin/mqnamesrv -c ${rocketmq_home}/conf/namesrv.properties
ExecStop=${rocketmq_home}/bin/mqshutdown namesrv

[Install]
WantedBy=multi-user.target
EOF

    echo_info 生成${unit_file_name_broker}文件用于systemd控制
    cat >/usr/lib/systemd/system/${unit_file_name_broker} <<EOF
[Unit]
Description=rocketmq borker
After=network.target

[Service]
Type=simple
# 如要配置多主多从，则将配置文件替换为${rocketmq_home}/conf/{2m-2s-async  2m-2s-sync  2m-noslave}下的配置文件
# ExecStart=${rocketmq_home}/bin/mqbroker -c ${rocketmq_home}/conf/broker.conf
ExecStart=${rocketmq_home}/bin/mqbroker -c ${rocketmq_home}/conf/2m-2s-async/broker-a.properties
ExecStop=/usr/local/rocketmq/bin/mqshutdown broker

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    echo_warning 如需配置多主多从，请自行修改unit file中-c参数中的配置
    echo_info rockermq已部署完毕，相关信息如下：
    echo -e "\033[37m                  nameserver端口：${nameserver_port}\033[0m"
    echo -e "\033[37m                  nameserver启动：systemctl start ${unit_file_name_nameserver}\033[0m"
    echo -e "\033[37m                  broker端口：${broker_port}\033[0m"
    echo -e "\033[37m                  broker启动：systemctl start ${unit_file_name_broker}\033[0m"
}

function binary_install() {
    download_tar_gz ${src_dir} https://mirrors.tuna.tsinghua.edu.cn/apache/rocketmq/${rocketmq_version}/rocketmq-all-${rocketmq_version}-bin-release.zip
    echo_info 检测解压工具
    unar -v &> /dev/null
    if [ $? -ne 0 ];then
        yum install -y epel-release
        yum install -y unar
        if [ $? -ne 0 ];then
            echo_error unar安装失败，请检查网络
            exit 1
        fi
    fi
    cd ${file_in_the_dir}
    unar rocketmq-all-${rocketmq_version}-bin-release.zip
    mv rocketmq-all-${rocketmq_version}-bin-release ${rocketmq_home}
    add_user_and_group ${sys_user}

    echo_info 修改rocketmq日志目录
    cd ${rocketmq_home}
    mkdir -p {logs,store/{commitlog,consumequeue}}
    sed -i 's#\${user.home}#'${rocketmq_home}'/logs#g' ${rocketmq_home}/conf/*.xml

    echo_info 修改broker初始化堆栈大小
    sed -i 's#JAVA_OPT="${JAVA_OPT} -server -Xms.*#JAVA_OPT="${JAVA_OPT} -server -Xms'${broker_java_xms}' -Xmx'${broker_java_xmx}' -Xmn'${broker_java_xmn}'"#g' ${rocketmq_home}/bin/runbroker.sh

    get_machine_ip
    grep "${nameserver_dns_name}" /etc/hosts &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 配置hosts文件
        echo "${machine_ip}    ${nameserver_dns_name}" >> /etc/hosts
    fi

    echo_info 生成nameserver配置文件
    cat > ${rocketmq_home}/conf/namesrv.properties << EOF
listenPort=${nameserver_port}
EOF

    echo_info 优化broker配置文件
    cat > ${rocketmq_home}/conf/2m-2s-async/broker-a.properties << EOF
# 所属集群的名字
brokerClusterName=my-rocketmq-cluster
# Broker的名称
brokerName=broker-a
# brokerId为0表示Master，>0表示Slave。配置slave的话记得下面的brokerRole参数修改为brokerRole=SLAVE
brokerId=0
# Broker对外服务的监听端口
listenPort=${broker_port}
# NameServer地址，使用分号分隔
# namesrvAddr=${nameserver_dns_name}:${nameserver_port};${nameserver_dns_name}-2:${nameserver_port}
namesrvAddr=${nameserver_dns_name}:${nameserver_port}
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

    generate_unit_file

}

check_jdk
is_run_rocketmq
binary_install