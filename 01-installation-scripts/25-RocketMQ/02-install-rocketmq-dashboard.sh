#!/bin/bash

# 目录配置
src_dir=$(pwd)/00src00
rocketmq_dashboard_home=$(pwd)/rocketmq-dashboard
rocketmq_dashboard_data_path=${rocketmq_dashboard_home}/data
rocketmq_dashboard_port=8228
rocketmq_web_user=admin
rocketmq_web_pass=dashboard
# 以什么用户启动rockermq-dashboard
sys_user=rocketmq
unit_file_name=rmq_dashboard.service
xms=512m
xmx=512m


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

# 定制
function download_tar_gz(){
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IsS $2 | head -1 | awk '{print $2}')
    if [ $http_code -eq 404 ];then
        echo_error $2
        echo_error 服务端文件不存在，退出
        exit 98
    fi
    
    download_file_name=rocketmq-dashboard-master.zip
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
            wget $2 -O rocketmq-dashboard-master.zip
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
                wget $2 -O rocketmq-dashboard-master.zip
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

function is_run_rocketmq_dashboard() {
    ps -ef | grep ${rocketmq_dashboard_home}/ | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到rocketmq_dashboard正在运行中，退出
        exit 3
    fi

    if [ -d ${rocketmq_dashboard_home} ];then
        echo_error 检测到目录${rocketmq_dashboard_home}，请检查是否重复安装，退出
        exit 4
    fi

    netstat -tnlp | grep -E ":${rocketmq_dashboard_port}[[:space:]]" &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到${rocketmq_dashboard_port}端口被占用，退出
        exit 5
    fi
}

function check_unzip() {
    unzip -h &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装解压工具unzip
        yum install -y unzip
    fi
}

function config_rocketmq_dashboard() {
    # 默认已经在rocketmq-dashboard目录下了
    sed -i 's#  port: 8080#  port: '${rocketmq_dashboard_port}'#' src/main/resources/application.yml
    sed -i 's#      - 127.0.0.1:9876#      - '${rocketmq_namesrv_addr}'#' src/main/resources/application.yml
    sed -i 's#    dataPath: /tmp/rocketmq-console/data#    dataPath: '${rocketmq_dashboard_data_path}'#' src/main/resources/application.yml
    if [[ -n ${rocketmq_proxy_addr} ]];then
        sed -i 's#    proxyAddr: 127.0.0.1:8080#    proxyAddr: '${rocketmq_proxy_addr}'#' src/main/resources/application.yml
        sed -i 's#      - 127.0.0.1:8080#      - '${rocketmq_proxy_addr}'#' src/main/resources/application.yml
    fi
    sed -i 's#    loginRequired: false#    loginRequired: true#' src/main/resources/application.yml
    sed -i 's#\${user.home}#'${rocketmq_dashboard_home}'/logs#g' src/main/resources/logback.xml
    cat > ${rocketmq_dashboard_data_path}/users.properties << EOF
# 该文件支持热修改，即添加和修改用户时，不需要重新启动dashboard
# 格式， 每行定义一个用户， username=password[,N]  #N是可选项，可以为0 (普通用户)； 1 （管理员）
${rocketmq_web_user}=${rocketmq_web_pass},1
EOF
}

function check_ip_legeal() {
    if [[ ${1} == "" ]];then
        echo_error 未输入ip，退出
        exit 3
    fi
    # if [[ ! ${1} =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
    #     echo_error 错误的ip格式，退出
    #     exit 4
    # fi
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
    echo_info 生成${unit_file_name}文件用于systemd控制
    cat >/usr/lib/systemd/system/${unit_file_name} <<EOF
[Unit]
Description=rocketmq-dashboard
After=network.target

[Service]
Type=simple
ExecStart=$JAVA_HOME/bin/java -Xms${xms} -Xmx${xmx} -jar ${rocketmq_dashboard_home}/rocketmq-dashboard.jar
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    get_machine_ip
    echo_info rockermq-dashboard已部署完毕，相关信息如下：
    echo -e "\033[37m                  启动命令：systemctl start ${unit_file_name}\033[0m"
    echo -e "\033[37m                  访问地址：http://${machine_ip}:${rocketmq_dashboard_port}\033[0m"
    echo -e "\033[37m                  登录账号：${rocketmq_web_user}"
    echo -e "\033[37m                  登录密码：${rocketmq_web_pass}"
}

function download_and_compile() {
    [ -d ${rocketmq_dashboard_data_path} ] || mkdir -p ${rocketmq_dashboard_data_path}

    echo_info "如果下载不成功，可通过其他方式下载后，放在$(pwd)/目录，或${src_dir}/目录下，再执行本脚本"
    download_tar_gz ${src_dir} https://codeload.github.com/apache/rocketmq-dashboard/zip/refs/heads/master
    cd ${file_in_the_dir}

    check_unzip
    echo_info 解压rocketmq-dashboard
    unzip rocketmq-dashboard-master.zip
    cd rocketmq-dashboard-master

    echo_info 请输入rocketmq nameserver的IP:port
    read rocketmq_namesrv_addr
    check_ip_legeal ${rocketmq_namesrv_addr}

    echo_info 请输入rocketmq proxy的IP:port，如未部署proxy请直接敲回车键：
    read rocketmq_proxy_addr

    echo_info 调整rockermq-dashboard配置
    config_rocketmq_dashboard

    echo_info 编译rocketmq-dashboard
    echo_warning 编译需要下载node，需要配置代理才能成功下载！
    echo_warning 常用代理方式，修改环境变量 HTTP_PROXY 和 HTTPS_PROXY
    mvn clean package -Dmaven.test.skip=true
    if [[ $? -ne 0 ]];then
        echo_warning '常规编译失败，尝试添加 -Dcheckstyle.skip=true 选项后，重新编译'
        mvn clean package -Dmaven.test.skip=true -Dcheckstyle.skip=true
    fi

    echo_info 拷贝jar包
    cp -a target/rocketmq-dashboard-1.0.1-SNAPSHOT.jar ${rocketmq_dashboard_home}/rocketmq-dashboard.jar

    add_user_and_group ${sys_user}
    echo_info 部署目录授权
    chown -R ${sys_user}:${sys_user} ${rocketmq_dashboard_home}

    echo_info 清理解压文件
    cd
    rm -rf ${file_in_the_dir}/rocketmq-dashboard-master
}

function main() {
    is_run_rocketmq_dashboard
    check_java_and_maven
    download_and_compile
    generate_unit_file
}

main

