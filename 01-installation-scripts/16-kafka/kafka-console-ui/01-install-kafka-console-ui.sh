#!/bin/bash

kafka_console_ui_version=1.0.12
# github
# download_url=https://github.com/xxd763795151/kafka-console-ui/releases/download/v${kafka_console_ui_version}/kafka-console-ui-${kafka_console_ui_version}.zip
# gitee
download_url=https://gitee.com/xiaodong_xu/kafka-console-ui/releases/download/v${kafka_console_ui_version}/kafka-console-ui-${kafka_console_ui_version}.zip
deploy_dir=$(pwd)/kafka_console_ui
src_dir=$(pwd)/00src00
# 服务端口
service_port=7766
# 以什么用户启动
sys_user=kafka
# 堆内存配置
service_xms=512m
service_xmx=512m

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
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
    # 阻止配置更新弹窗
    export UCF_FORCE_CONFFOLD=1
    # 阻止应用重启弹窗
    export NEEDRESTART_SUSPEND=1
elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)
elif [[ -e /etc/almalinux-release ]]; then
    os="alma"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/almalinux-release)
else
	true
fi

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

function gen_systemd_unitfile() {
    JAVA_CMD=$(which java | head -1)
    base_name=$(basename ${deploy_dir})

    echo_info 生成 unitfile
    cat >/etc/systemd/system/kafka-console-ui.service <<EOF
[Unit]
Description=kafka-console-ui
Documentation=https://github.com/xxd763795151/kafka-console-ui
After=network.target
 

[Service]
Type=simple
User=${sys_user}
Group=${sys_user}
WorkingDirectory=${deploy_dir}
ExecStart=${JAVA_CMD} -Xms${service_xms} -Xmx${service_xmx} -Dserver.port=${service_port} -Dfile.encoding=utf-8 -jar ${deploy_dir}/lib/kafka-console-ui.jar --spring.config.location=${deploy_dir}/config/application.yml --logging.home=${deploy_dir} --data.dir=${deploy_dir} kafka-console-ui-process-flag:${base_name}
ExecStop=/usr/bin/pkill -f kafka-console-ui-process-flag:${base_name}
Restart=on-failure
TimeoutStopSec=15
 
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

java -version &> /dev/null
if [ $? -ne 0 ];then
    echo_error 未检测到java，请先部署java
    exit 1
fi

if [ -d ${deploy_dir} ];then
    echo_error 检查到目录 ${deploy_dir}，请确认是否重复安装
    exit 1
fi

if ! unzip -h &> /dev/null;then
    echo_info 安装unzip
    if [[ $os == "centos" ]];then
        yum install -y unzip
    elif [[ $os == 'rocky' || $os == 'alma' ]];then
        dnf install -y unzip
    elif [[ $os == "ubuntu" ]];then
        apt update
        apt install -y unzip
    else
        echo_error 未检测到unzip命令，请先安装
        exit 1
    fi
fi

add_user_and_group ${sys_user}

echo_info 下载kafka-console-ui
download_tar_gz $src_dir $download_url
cd ${file_in_the_dir}

echo_info 解压kafka-console-ui
unzip kafka-console-ui-${kafka_console_ui_version}.zip
mv kafka-console-ui ${deploy_dir}
chown -R ${sys_user}:${sys_user} ${deploy_dir}

gen_systemd_unitfile

get_machine_ip

echo_info kafka-console-ui部署成功
echo -e "\033[37m                  启动命令：systemctl start kafka-console-ui\033[0m"
echo -e "\033[37m                  访问地址：http://${machine_ip}:${service_port}\033[0m"