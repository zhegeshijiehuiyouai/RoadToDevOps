#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
grafana_port=3000
grafana_version=7.4.3
# 部署grafana的目录
grafana_home=$(pwd)/grafana-${grafana_version}
sys_user=grafana
unit_file_name=grafana-server.service



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

function is_run_grafana() {
    ps -ef | grep ${grafana_home} | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到grafana正在运行中，退出
        exit 3
    fi

    if [ -d ${grafana_home} ];then
        echo_error 检测到目录${grafana_home}，请检查是否重复安装，退出
        exit 4
    fi

    if [ -d /var/lib/grafana/ ];then
        # 由于grafana-cli的原因，需要做一个软链接/var/lib/grafana/plugins，故排除此目录
        if [ $(ls /var/lib/grafana/ | grep -v plugins | wc -l) -gt 1 ];then
            echo_error 检测到/var/lib/grafana/目录不为空，请检查是否重复安装，退出
            exit 5
        fi
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

function generate_unit_file_and_start() {
    get_machine_ip

    echo_info 生成${unit_file_name}文件用于systemd控制
    cat >/usr/lib/systemd/system/${unit_file_name} <<EOF
[Unit]
Description=Grafana instance -- script from https://github.com/zhegeshijiehuiyouai/RoadToDevOps
Documentation=http://docs.grafana.org

[Service]
User=grafana
Group=grafana
Type=notify
Restart=always
WorkingDirectory=${grafana_home}
ExecStart=${grafana_home}/bin/grafana-server
LimitNOFILE=10000
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF
    echo_info ${grafana_home} 目录授权
    chown -R ${sys_user}:${sys_user} ${grafana_home}

    echo_info 配置命令软链接
    rm -rf /usr/local/bin/grafana-cli
    rm -rf /usr/local/bin/grafana-server
    ln -s ${grafana_home}/bin/grafana-cli /usr/local/bin/grafana-cli
    ln -s ${grafana_home}/bin/grafana-server /usr/local/bin/grafana-server

    systemctl daemon-reload
    echo_info 启动grafana
    systemctl start ${unit_file_name}
    if [ $? -ne 0 ];then
        echo_error grafana启动失败，请检查
        exit 1
    fi
    systemctl enable ${unit_file_name} &> /dev/null

    # 由于grafana-cli中将插件目录写死了，所以做这条软链接。
    # 又由于启动grafana后才会生成插件目录，所以本命令写在启动之后
    ln -s ${grafana_home}/data/plugins /var/lib/grafana/plugins

    echo_info prometheus已成功部署并启动，相关信息如下：
    echo -e "\033[37m                  启动命令：systemctl start ${unit_file_name}\033[0m"
    echo -e "\033[37m                  端口：${grafana_port}\033[0m"
    echo -e "\033[37m                  部署目录：${grafana_home}\033[0m"
    echo -e "\033[37m                  grafana访问地址：http://${machine_ip}:${grafana_port}/\033[0m"
    echo -e "\033[37m                  默认账号密码：admin / admin\033[0m"
    echo -e "\033[37m                  模板获取网址：https://grafana.com/grafana/dashboards\033[0m"
    echo -e "\033[37m                  推荐模板id - 主机基础监控：9276/\033[0m"
}

function config_grafana() {
    echo_info 调整grafana配置
    sed -i 's/^http_port.*/http_port = '${grafana_port}'/' ${grafana_home}/conf/defaults.ini

    if [ ! -d /var/lib/grafana ];then
        mkdir -p /var/lib/grafana
        chown -R ${sys_user}:${sys_user} /var/lib/grafana
    else
        rm -rf /var/lib/grafana/plugins
    fi
}

function download_and_config() {
    download_tar_gz ${src_dir} https://dl.grafana.com/oss/release/grafana-${grafana_version}.linux-amd64.tar.gz
    cd ${file_in_the_dir}
    untar_tgz grafana-${grafana_version}.linux-amd64.tar.gz
    mv grafana-${grafana_version} ${grafana_home}

    add_user_and_group ${sys_user}
    config_grafana

    generate_unit_file_and_start
}

function install_grafana() {
    is_run_grafana
    download_and_config
}

install_grafana