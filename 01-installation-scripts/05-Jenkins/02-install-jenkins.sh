#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
tomcat_version=8.5.64
jenkins_stable_version=2.277.2
jenkins_root=$(pwd)/jenkins
jenkins_home=${jenkins_root}/tomcat
jenkins_data_home=${jenkins_root}/data
tomcat_shutdown_port=6005
# jenkins使用tomcat启动，所以tomcat的端口也就是jenkins的端口
jenkins_port=16080
# 启动服务的用户
sys_user=jenkins
unit_file_name=jenkins.service
# 内存配置
Xms=512M
Xmx=1024M

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
        exit 1
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

function add_user_and_group(){
    if id -g ${1} >/dev/null 2>&1; then
        echo_warning ${1}组已存在
    else
        groupadd ${1} &> /dev/null
        echo_info 创建${1}组
    fi
    if id -u ${1} >/dev/null 2>&1; then
        echo_error ${1}用户已存在，请确认${1}的家目录无重要数据后，删除${1}用户及其家目录
        exit 2
    else
        useradd -M -g ${1} -s /bin/bash -d ${jenkins_data_home} ${1} &> /dev/null
        echo_info 创建${1}用户
    fi
}

function is_run_jenkins() {
    java -version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到java，请先部署java
        exit 3
    fi

    ps -ef | grep ${jenkins_home} | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到jenkins正在运行中，退出
        exit 4
    fi
    if [ -d ${jenkins_home} ];then
        echo_error 检测到目录 ${jenkins_home}，请检查是否重复安装，退出
        exit 5
    fi
    if [ -d ${jenkins_data_home} ];then
        echo_error 检测到目录 ${jenkins_data_home}，请检查是否重复安装，退出
        exit 6
    fi

    [ -d ${jenkins_data_home} ] || mkdir -p ${jenkins_data_home}
}

function get_machine_ip() {
    function input_machine_ip_fun() {
        read input_machine_ip
        machine_ip=${input_machine_ip}
        if [[ ! $machine_ip =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
            echo_error 错误的ip格式，退出
            exit 7
        fi
    }
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

function generate_unit_file_and_start() {
    echo_info 生成${unit_file_name}文件用于systemd控制
    cat >/usr/lib/systemd/system/${unit_file_name} <<EOF
[Unit]
Description=Jenkins -- script from https://github.com/zhegeshijiehuiyouai/RoadToDevOps
After=syslog.target network.target

[Service]
Type=forking

Environment=JAVA_HOME=$JAVA_HOME
Environment=CATALINA_HOME=${jenkins_home}
Environment=CATALINA_BASE=${jenkins_home}
Environment='CATALINA_OPTS=-Xms${Xms} -Xmx${Xmx} -server -XX:+UseParallelGC -Djava.awt.headless=true'

ExecStart=${jenkins_home}/bin/startup.sh
ExecStop=${jenkins_home}/bin/shutdown.sh

User=${sys_user}
Group=${sys_user}
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    echo_info ${jenkins_root} 目录授权
    chown -R ${sys_user}:${sys_user} ${jenkins_root}
    systemctl daemon-reload
    
    echo_info 初始化jenkins
    systemctl start ${unit_file_name}
    if [ $? -ne 0 ];then
        echo_error jenkins启动失败，请检查
        exit 8
    fi

    get_machine_ip

    ln -s ${jenkins_data}/.jenkins/ ${jenkins_data_home}/jenkins_data
    while :
    do
        tail -1 ${jenkins_home}/logs/catalina.out | grep "Jenkins is fully up and running" &> /dev/null
        if [ $? -eq 0 ];then
            echo
            echo_info jenkins已成功部署并启动，相关信息如下：
            echo -e "\033[37m                  启动命令：systemctl start ${unit_file_name}\033[0m"
            echo -e "\033[37m                  部署目录：${jenkins_root}\033[0m"
            echo -e "\033[37m                  访问地址：http://${machine_ip}:${jenkins_port}/jenkins\033[0m"
            exit 9
        fi
        echo -n "."
        sleep 3
    done
}

function install_jenkins() {
    add_user_and_group ${sys_user}

    download_tar_gz ${src_dir} https://mirrors.cloud.tencent.com/apache/tomcat/tomcat-$(echo $tomcat_version | cut -d . -f 1)/v${tomcat_version}/bin/apache-tomcat-${tomcat_version}.tar.gz
    cd ${file_in_the_dir}
    untar_tgz apache-tomcat-${tomcat_version}.tar.gz
    mv apache-tomcat-${tomcat_version} ${jenkins_home}
    cd ${back_dir}
    echo_info 清理默认项目
    rm -rf ${jenkins_home}/webapps/*
    echo_info 调整jenkins的tomcat配置
    sed -i 's/Connector port=\"8080\"/Connector port=\"'${jenkins_port}'\"/' ${jenkins_home}/conf/server.xml
    sed -i 's/Server port=\"8005\" shutdown="SHUTDOWN"/Server port="'${tomcat_shutdown_port}'" shutdown="SHUTDOWN"/' ${jenkins_home}/conf/server.xml

    # 下载jenkins
    download_tar_gz ${src_dir} https://mirrors.cloud.tencent.com/jenkins/war-stable/${jenkins_stable_version}/jenkins.war
    cp ${file_in_the_dir}/jenkins.war ${jenkins_home}/webapps/

    generate_unit_file_and_start
}

is_run_jenkins
install_jenkins