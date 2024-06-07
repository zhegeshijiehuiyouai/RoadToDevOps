#!/bin/bash

# 腾讯镜像只有最新2-3个版本，找老版本的话，要去官网：https://kafka.apache.org/downloads
download_url=https://mirrors.cloud.tencent.com/apache/kafka/3.7.0/kafka_2.13-3.7.0.tgz
src_dir=$(pwd)/00src00
kafka_port=9092
kafka_jmx_port=9988

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
# $os_version变量并不总是存在，但为了方便，仍然保留这个变量
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	# os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)

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
                elif [[ $os == "rocky" ]];then
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
                    elif [[ $os == "rocky" ]];then
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

function check_dir() {
    if [ -d $1 ];then
        echo_error 目录 $1 已存在，退出
        exit 2
    fi
}

function check_port_2181() {
    ss -tnlp | grep 2181 &>/dev/null
    if [ $? -eq 0 ];then
        echo_error zookeeper 2181 端口已被占用，无法继续，退出
        exit 6
    fi
}
function generate_kafka_service() {
    echo_info 生成kafka.service文件用于systemd控制
    cat >/etc/systemd/system/kafka.service <<EOF
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

#-------------------------------------------------
function input_machine_ip_fun() {
    read -e input_machine_ip
    machine_ip=${input_machine_ip}
    if [[ ! $machine_ip =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
        echo_error 错误的ip格式，退出
        exit 7
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

function show_installed_kafka_info() {
    echo_warning 由于bash特性限制，在本终端使用 kafka 的命令，需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端
    echo_info kafka已部署完成，以下是kafka环境信息：
    if [ $confirm_zk_choice -eq 2 ];then
        # 外部zookeeper
        echo -e "\033[37m                  zookeeper信息：外置zookeeper -- ${insert_zk_addrs}\033[0m"
    elif [ $confirm_zk_choice -eq 3 ];then
        # 内置zookeeper
        echo -e "\033[37m                  zookeeper信息：内置zookeeper -- ${machine_ip}:2181\033[0m"
        echo -e "\033[37m                  zookeeper启动命令：systemctl start kafka-zookeeper\033[0m"
    fi
    echo -e "\033[37m                  kafka端口：${kafka_port}\033[0m"
    echo -e "\033[37m                  kafka启动命令：systemctl start kafka\033[0m"
}

function config_kafka_common() {
    cd ${back_dir}/${bare_name}/config/
    sed -i 's#^log.dirs=.*#log.dirs='${back_dir}'/'${bare_name}'/logs#g' server.properties
    sed -i 's@^#listeners=PLAINTEXT://:9092.*@listeners=PLAINTEXT://'${machine_ip}':'${kafka_port}'@g' server.properties
    # 下面这个可以不设置，不设置的话，取listeners的值
    # sed -i 's@^#advertised.listeners=PLAINTEXT://your.host.name:9092.*@advertised.listeners=PLAINTEXT://'${machine_ip}':'${kafka_port}'@g' server.properties
}

# 内置kafka
function config_kafka_with_internal_zk() {
    config_kafka_common
    cd ${back_dir}/${bare_name}/config/
    sed -i 's#^dataDir=.*#dataDir=${back_dir}/'${bare_name}'/'${zookeeper_data_dir}'#g' zookeeper.properties

    cat >/etc/systemd/system/kakfa-zookeeper.service <<EOF
[Unit]
Description=Apache Zookeeper server (Kafka)
Documentation=http://zookeeper.apache.org
Requires=network.target remote-fs.target
After=network.target remote-fs.target
 
[Service]
Type=simple
User=kafka
Group=kafka
ExecStart=${back_dir}/${bare_name}/bin/zookeeper-server-start.sh ${back_dir}/${bare_name}/config/zookeeper.properties
ExecStop=${back_dir}/${bare_name}/bin/zookeeper-server-stop.sh
 
[Install]
WantedBy=multi-user.target
EOF
    generate_kafka_service
}

# 外置kafka
function config_kafka_with_external_zk() {
    # 获取zk地址
    insert_zk_addrs=""
    for i in ${zk_addrs[@]};do
        insert_zk_addrs=${insert_zk_addrs},$i
    done
    insert_zk_addrs=$(echo $insert_zk_addrs | sed 's#^.##g')

    config_kafka_common
    cd ${back_dir}/${bare_name}/config/
    sed -i 's#^zookeeper.connect=.*#zookeeper.connect='${insert_zk_addrs}'#g' server.properties
    
    generate_kafka_service
}

function install_kafka() {
    get_machine_ip
    # 如果使用自带zk，那么需要先检测2181端口是否被占用
    if [ $confirm_zk_choice -eq 3 ];then
        check_port_2181
    fi

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

    if [[ ! "${file_in_the_dir}" == "${back_dir}" ]];then
        mv ${bare_name} ${back_dir}/${bare_name}
    fi

    cd ${back_dir}/${bare_name}
    echo_info 开启 kafka jmx
    sed -i '/^# limitations under the License./a export JMX_PORT='${kafka_jmx_port}'' bin/kafka-server-start.sh

    echo_info 配置环境变量
    echo "export PATH=\$PATH:${back_dir}/${bare_name}/bin" > /etc/profile.d/kafka.sh

    add_user_and_group kafka
    [ -d ${back_dir}/${bare_name}/logs ] || mkdir -p ${back_dir}/${bare_name}/logs

########### 根据使用外部zk还是内置zk进行调整
    echo_info kafka配置调整
    if [ $confirm_zk_choice -eq 2 ];then
        # 外部zookeeper
        config_kafka_with_external_zk
    elif [ $confirm_zk_choice -eq 3 ];then
        # 内置zookeeper
        zookeeper_data_dir=zookeeper-data
        [ -d ${back_dir}/${bare_name}/${zookeeper_data_dir} ] || mkdir -p ${back_dir}/${bare_name}/${zookeeper_data_dir}
        config_kafka_with_internal_zk
    fi

    echo_info 对 ${back_dir}/${bare_name} 目录进行授权
    chown -R kafka:kafka ${back_dir}/${bare_name}
    systemctl daemon-reload
    show_installed_kafka_info
}

function accept_zk_addr() {
    read -e zk_addr
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
    echo "1 - 未部署zookeeper，退出去部署zookeeper"
    echo "2 - 已部署zookeeper，输入zookeeper地址"
    echo "3 - 使用kafka自带的zookeeper"
    function input_confirm_zk_number() {
        read -p "输入数字选择(q 键退出)：" -e confirm_zk_choice
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
        3)
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
