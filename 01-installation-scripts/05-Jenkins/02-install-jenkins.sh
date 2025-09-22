#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
jenkins_stable_version=2.492.2
jenkins_home=$(pwd)/jenkins
jenkins_log_dir=${jenkins_home}/logs
jenkins_port=6080
# 启动服务的用户
sys_user=jenkins
sys_user_group=jenkins
unit_file_name=jenkins.service
# 内存配置
Xms=1024M
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
function check_downloadfile() {
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IksS $1 | head -1 | awk '{print $2}')
    if [ $http_code -eq 404 ];then
        echo_error $1
        echo_error 服务端文件不存在，退出
        exit 98
    fi
}
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
                if [[ $os == "centos" ]];then
                    yum install -y wget
                elif [[ $os == "ubuntu" ]];then
                    apt install -y wget
                elif [[ $os == 'rocky' || $os == 'alma' ]];then
                    dnf install -y wget
                fi
            fi
            check_downloadfile $2
            wget --no-check-certificate $2
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
                    if [[ $os == "centos" ]];then
                        yum install -y wget
                    elif [[ $os == "ubuntu" ]];then
                        apt install -y wget
                    elif [[ $os == 'rocky' || $os == 'alma' ]];then
                        dnf install -y wget
                    fi
                fi
                check_downloadfile $2
                wget --no-check-certificate $2
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
        true
    else
        groupadd ${1}
        echo_info 创建 ${1} 组
    fi

    if id -u ${2} >/dev/null 2>&1; then
        true
    else
        useradd -M -g ${1} -s /sbin/nologin ${2}
        echo_info 创建 ${2} 用户
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

    [ -d ${jenkins_home} ] || mkdir -p ${jenkins_log_dir}
}

function get_machine_ip() {
    machine_ip=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
}

function generate_unit_file_and_start() {
    echo_info 生成${unit_file_name}文件用于systemd控制
    cat >/usr/lib/systemd/system/${unit_file_name} <<EOF
[Unit]
Description=Jenkins Continuous Integration Server
After=network.target

[Service]
User=${sys_user}
Group=${sys_user_group}
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="JENKINS_HOME=${jenkins_home}"
WorkingDirectory=${jenkins_home}
ExecStart=/bin/sh -c "${JAVA_HOME}/bin/java -Djava.awt.headless=true -Xms1024M -Xmx1024M -jar ${jenkins_home}/jenkins.war --httpPort=6080 >> ${jenkins_log_dir}/jenkins.log 2>&1"
ExecStop=/bin/kill -TERM \${MAINPID}
# 当 Jenkins 正常退出（如收到 SIGTERM）时返回 143，保证 systemd 能正确处理退出状态
SuccessExitStatus=143
TimeoutStopSec=10
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    echo_info ${jenkins_home} 目录授权
    chown -R ${sys_user}:${sys_user} ${jenkins_home}
    systemctl daemon-reload
    
    echo_info 启动jenkins
    systemctl start ${unit_file_name}
    if [ $? -ne 0 ];then
        echo_error jenkins启动失败，请检查
        exit 8
    fi

    get_machine_ip
    sleep 1
    echo
    echo_info jenkins已成功部署并启动，请尽快访问web完成初始化，相关信息如下：
    echo -e "\033[37m                  启动命令：systemctl start ${unit_file_name}\033[0m"
    echo -e "\033[37m                  部署目录：${jenkins_home}\033[0m"
    echo -e "\033[37m                  访问地址：http://${machine_ip}:${jenkins_port}\033[0m"
}

function install_jenkins() {
    add_user_and_group ${sys_user_group} ${sys_user}
    # 下载jenkins
    download_tar_gz ${src_dir} https://mirrors.cloud.tencent.com/jenkins/war-stable/${jenkins_stable_version}/jenkins.war
    cp ${file_in_the_dir}/jenkins.war ${jenkins_home}/

    generate_unit_file_and_start
}

is_run_jenkins
install_jenkins