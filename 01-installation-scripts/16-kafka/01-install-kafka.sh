#!/bin/bash

download_url=https://mirrors.cloud.tencent.com/apache/kafka/2.7.0/kafka_2.13-2.7.0.tgz
src_dir=$(pwd)/00src00

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

function check_dir() {
    if [ -d $1 ];then
        echo_error 目录 $1 已存在，退出
        exit 2
    fi
}

function install_kafka() {
    java -version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到jdk，请先部署jdk
        exit 1
    fi

    bare_name=$(basename $download_url | sed 's/\.tgz//')

    echo_info 下载 ${bare_name}，【 更多版本 】可前往 https://mirrors.cloud.tencent.com/apache/kafka/ 下载
    download_tar_gz $src_dir $download_url

    check_dir ${back_dir}/${bare_name}

    cd ${file_in_the_dir}
    untar_tgz $(basename ${download_url})
    mv ${bare_name} ${back_dir}/${bare_name}

    cd ${back_dir}/${bare_name}
    add_user_and_group kafka

    [ -d ${back_dir}/${bare_name}/logs ] || mkdir -p ${back_dir}/${bare_name}/logs
    echo_info kafka配置调整

    # 获取zk地址
    insert_zk_addrs=""
    for i in ${zk_addrs[@]};do
        insert_zk_addrs=${insert_zk_addrs},$i
    done
    insert_zk_addrs=$(echo $insert_zk_addrs | sed 's#^.##g')

    cat > /tmp/.my_kafka_config_change << EOF
cd ${back_dir}/${bare_name}/config/
sed -i 's#^log.dirs=.*#log.dirs=${back_dir}/${bare_name}/logs#g' server.properties
sed -i 's#^zookeeper.connect=.*#zookeeper.connect=${insert_zk_addrs}#g' server.properties
EOF
    /bin/bash /tmp/.my_kafka_config_change
    rm -f /tmp/.my_kafka_config_change

    echo_info 对 ${back_dir}/${bare_name} 目录进行授权
    chown -R kafka:kafka ${back_dir}/${bare_name}

    echo_info 生成kafka.service文件用于systemd控制
    cat >/usr/lib/systemd/system/kafka.service <<EOF
[Unit]
Description=Kafka, install script from https://github.com/zhegeshijiehuiyouai/RoadToDevOps

[Service]
User=kafka
Group=kafka
Type=simple
ExecStart=${back_dir}/${bare_name}/bin/kafka-server-start.sh ${back_dir}/${bare_name}/config/server.properties
ExecStop=${back_dir}/${bare_name}/bin/kafka-server-stop.sh
Restart=always

[Install]
WantedBy=multi-user.target

EOF
}

function accept_zk_addr() {
    read zk_addr
    if [ "" != "$zk_addr" ];then
        # 进入此处，表示用户输入了值，需要重置空行标志位
        zk_null_flag=0
        zk_addrs[$zk_num]=$zk_addr
        let zk_num++
        accept_zk_addr
    else
        if [ $zk_null_flag -eq 1 ];then
            # 第二次输入空行，会进入到此
            return
        else
            # 第一次输入空行，会进入到此，设置flag
            zk_null_flag=1
            accept_zk_addr
        fi
    fi
}

function check_zk_addr_is_legal() {
    if [[ "${zk_addrs[0]}" == "" ]];then
        echo_error 没有输入zookeeper地址
        exit 5
    fi
    for i in ${zk_addrs[@]};do
        if [[ ! $i =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3}:[0-9]{1,5}/?.* ]];then
            echo_error $i 不符合zookeeper地址格式，退出
            exit 4
        fi
    done
}

function start_the_installation_by_confirm_zk() {
    echo_info 
    echo kafka需要连接zookeeper，请选择zookeeper部署情况：
    echo "1 - 未部署zookeeper"
    echo "2 - 已部署zookeeper"
    function input_confirm_zk_number() {
        read -p "输入数字选择(q 键退出)：" confirm_zk_choice
        case $confirm_zk_choice in
        1)
            echo_warning 请部署好zookeeper后再执行此脚本
            exit 3
            ;;
        2)
            # 接收zk地址的数组的下标
            zk_num=0
            # 该标志位用户是否输入了空行，输入两次空行则表示没有zk地址了，继续下一步
            zk_null_flag=0
            echo_info
            echo "请输入zookeeper地址(ip:port[/path])，如有多个，请回车后继续输入，连输两次空行继续下一步部署操作："
            accept_zk_addr
            # 检测输入的地址是否是zookeeper地址的格式
            check_zk_addr_is_legal
            echo_info 开始部署kafka
            install_kafka
            ;;
        q|Q)
            echo_info 用户退出
            exit
            ;;
        *)
            input_confirm_zk_number
            ;;
        esac
    }
    input_confirm_zk_number
}


# 主函数
start_the_installation_by_confirm_zk
