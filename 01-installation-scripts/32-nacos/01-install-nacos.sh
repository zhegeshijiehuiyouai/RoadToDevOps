#!/bin/bash

# 以下配置仅对二进制部署集群有效
src_dir=$(pwd)/00src00
nacos_mysql_ip=10.211.55.13
nacos_mysql_port=3306
nacos_mysql_db=nacos_config
nacos_mysql_user=root
nacos_mysql_pass=123456
nacos_version=2.0.3
nacos_home=$(pwd)/nacos
nacos_cluster="\
10.211.55.13:8848
10.211.55.14:8848
10.211.55.15:8848
"
# 运行nacos的用户
sys_user=nacos

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

#-------------------------------------------------
function input_machine_ip_fun() {
    read input_machine_ip
    machine_ip=${input_machine_ip}
    if [[ ! $machine_ip =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
        echo_error 错误的ip格式，退出
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
#-------------------------------------------------

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
            echo_info 下载 $download_file_name 至 $(pwd)/，若下载失败，请手动下载后上传至此目录
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
                echo_info 下载 $download_file_name 至 $(pwd)/，若下载失败，请手动下载后上传至此目录
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

function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
        exit 1
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
    check_git
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

function check_jdk() {
    echo_info jdk检测
    java -version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到jdk，请先部署jdk
        exit 1
    fi
}

function parse_cluster_info() {
    get_machine_ip
    for i in ${nacos_cluster};do
        echo ${i} | grep "${machine_ip}" &> /dev/null
        if [ $? -eq 0 ];then
            my_cluster_port=$(echo ${i} | awk -F":" '{print $2}')
            break
        fi
    done
    if [ -z ${my_cluster_port} ];then
        echo_error 请检查本机ip ${machine_ip} 是否在脚本集群配置中
        exit 1
    fi
}

function pre_install_check() {
    check_jdk
    parse_cluster_info
    if [ -d ${nacos_home} ];then
        echo_error 检测到目录 ${nacos_home}，请确认是否重复部署
        exit 1
    fi
    ss -tnlp | awk '{print $4}' | grep ${my_cluster_port} &> /dev/null
    if [ $? -eq 0 ];then
        echo_error nacos端口 ${my_cluster_port} 已被占用
        exit 1
    fi
    add_user_and_group ${sys_user}
}

function init_nacos_mysql() {
    mysql -h${nacos_mysql_ip} -P${nacos_mysql_port} -u${nacos_mysql_user} -p${nacos_mysql_pass} -e "drop database ${nacos_mysql_db};" &> /dev/null
    mysql -h${nacos_mysql_ip} -P${nacos_mysql_port} -u${nacos_mysql_user} -p${nacos_mysql_pass} -e "create database ${nacos_mysql_db};" &> /dev/null

    mysql -h${nacos_mysql_ip} -P${nacos_mysql_port} -u${nacos_mysql_user} -p${nacos_mysql_pass} -e "\
    USE ${nacos_mysql_db};\
    source conf/nacos-mysql.sql;" &> /dev/null

    if [ $? -eq 0 ];then
        echo_info nacos数据库初始化成功
    else
        echo_error nacos数据库初始化失败
        exit 1
    fi
}

function is_init_nacos_mysql() {
    echo_warning "是否初始化nacos数据库？默认不初始化 [y|N]"
    read USER_INPUT
    if [ ! -z ${USER_INPUT} ];then
        case ${USER_INPUT} in
            y|Y|yes)
                init_nacos_mysql
                ;;
            n|N|no)
                true
                ;;
            *)
                is_init_nacos_mysql
                ;;
        esac
    fi
}

function generate_unit_file() {
    cat >/usr/lib/systemd/system/nacos.service <<EOF
[Unit]
Description=nacos
After=network.target

[Service]
Type=forking
User=${sys_user}
Group=${sys_user}
ExecStart=${nacos_home}/bin/startup.sh -m standalone
ExecStop=${nacos_home}/bin/shutdown.sh
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

function install_cluster_by_binary() {
    pre_install_check
    download_tar_gz ${src_dir} https://github.com/alibaba/nacos/releases/download/${nacos_version}/nacos-server-${nacos_version}.tar.gz
    cd ${file_in_the_dir}
    untar_tgz nacos-server-${nacos_version}.tar.gz
    mv nacos ${nacos_home} && cd ${nacos_home}

    is_init_nacos_mysql
    
    echo_info 配置nacos
    :> conf/cluster.conf
    for i in ${nacos_cluster};do
        echo ${i} >> conf/cluster.conf
    done
    sed -i "s|^server.port=8848|server.port=${my_cluster_port}|g" conf/application.properties
    sed -i "s|^# db.num=1|db.num=1|g" conf/application.properties
    sed -i "s|^# db.url.0=jdbc:mysql://127.0.0.1:3306/nacos|db.url.0=jdbc:mysql://${nacos_mysql_ip}:${nacos_mysql_port}/${nacos_mysql_db}|g" conf/application.properties
    sed -i "s|^# db.user.0=nacos|db.user.0=${nacos_mysql_db}|g" conf/application.properties
    sed -i "s|^# db.password.0=nacos|db.password.0=${nacos_mysql_pass}|g" conf/application.properties
    sed -i "s|^nacos.core.auth.enabled=false|nacos.core.auth.enabled=true|g" conf/application.properties
    generate_unit_file
    echo_info nacos集群中的 ${machine_ip}:${my_cluster_port} 已部署完毕
    echo_info 启动命令：systemctl start nacos
}

function install_main_func(){
    read -p "请输入数字选择安装类型（如需退出请输入q）：" software
    case $software in
        1)
            install_by_docker
            ;;
        2)
            install_cluster_by_binary
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
echo -e "\033[36m[1]\033[32m docker-compose部署最新版nacos\033[0m"
echo -e "\033[36m[2]\033[32m 二进制包部署nacos集群\033[0m"
install_main_func
