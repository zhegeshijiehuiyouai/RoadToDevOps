#!/bin/bash
# 部署一个3节点的consul集群

src_dir=$(pwd)/00src00
my_dir=$(pwd)
consul_version=1.10.1
consul_home=${my_dir}/consul
# 数据中心名称
consul_datacenter=dc1
# 启动服务的用户
sys_user=consul
unit_file_name=consul.service



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

function check_unzip() {
    unzip -h &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装unzip
        yum install -y unzip
        if [ $? -ne 0 ];then
            echo_error unzip安装失败，请排查原因
            exit 2
        fi
    fi
}

function check_consul() {
    consul version &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 系统中已存在consul（$(whereis consul)），请确认是否重复安装
        exit 3
    fi

    if [ -d ${consul_home} ];then
        echo_error 检测到目录 ${consul_home}，请确认是否重复安装
        exit 4
    fi
}

# 通常配置
function set_consul_config() {
    cat > ${consul_home}/conf/consul.hcl << EOF
# agent 所在的数据中心
datacenter = "${consul_datacenter}"
# agent 存储状态的目录
data_dir = "${consul_home}/data"
# Consul 网络通信的加密密钥
# encrypt = "Luj2FZWwlt8475wD1WtwUQ=="
# 节点名
node_name = "$(hostname)_${machine_ip}"
# 客户端地址
client_addr = "0.0.0.0"
# 绑定本机ip
bind_addr= "${machine_ip}"
# 通告地址用于更改我们通告给集群中其他节点的地址，一般与bind_addr一致，如果出现特殊不一致的情况，手动指定就很有必要了
advertise_addr = "${machine_ip}"
#
# performance 参数允许调整不同 Consul 中子系统的性能
performance {
  # Consul 控制 Raft 计时的伸缩因子。设置为 1 会使 Raft 运行在高性能模式（默认值是 0.7），建议用于生产环境
  raft_multiplier = 1
}
EOF
    # 非server leader时添加
    echo "# 要加入的集群某个agent的地址" >> ${consul_home}/conf/consul.hcl
    if [ ! -z ${consul_leader_ip} ];then 
        echo "retry_join = [\"${consul_leader_ip}\"]" >> ${consul_home}/conf/consul.hcl
    else
        echo "# retry_join = [\"${consul_leader_ip}\"]" >> ${consul_home}/conf/consul.hcl
    fi

    chmod 640 ${consul_home}/conf/consul.hcl
}

# server配置
function set_server_config() {
    cat > ${consul_home}/conf/server.hcl << EOF
# 表示该 agent 运行在 server 模式还是 client  模式
server = true
# 提供 Consul UI 服务
ui = true
EOF
    # leader
    if [ ${consul_leader_tag} -eq 1 ];then
        echo "# 用来控制一个server是否在bootstrap模式，在一个datacenter中只能有一个server处于bootstrap模式，当一个server处于bootstrap模式时，可以自己选举为raft leader" >> ${consul_home}/conf/server.hcl
        echo "bootstrap = true" >> ${consul_home}/conf/server.hcl
    # folloer
    elif [ ${consul_leader_tag} -eq 2 ];then
        echo "# 在一个datacenter中期望提供的server节点数目，当该值提供的时候，consul一直等到达到指定sever数目的时候才会引导整个集群，该标记不能和bootstrap公用。集群中的所有server节点的该字段都应一致" >> ${consul_home}/conf/server.hcl
        echo "bootstrap_expect = 3" >> ${consul_home}/conf/server.hcl
    fi
    chmod 640 ${consul_home}/conf/server.hcl
}

# client配置
function set_client_config() {
    cat > ${consul_home}/conf/client.hcl << EOF
# 如有需要，自行手动添加
ui = true
EOF
    chmod 640 ${consul_home}/conf/client.hcl
}

function input_consul_leader_ip() {
    if [ ${consul_mode} -eq 1 ];then
        echo_info 请输入 consul leader 的 ip 地址：
    elif [ ${consul_mode} -eq 2 ];then
        echo_info 请输入任意一个 consul server 的 ip 地址：
    fi
    read consul_leader_ip
    if [[ ! ${consul_leader_ip} =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
        echo_error 错误的ip格式，退出
        exit 5
    fi
}

# 如果是consul服务端，选择是不是server的主节点
function choose_leader_or_follower() {
    echo -e "\033[31m该节点是否部署为主节点（注意：集群中主节点只能有一个）（y/n/q）：\033[0m"
    read consul_leader
    case ${consul_leader} in
        y|Y)
            echo_info 该节点将配置为 Leader
            consul_leader_tag=1
            ;;
        n|N)
            echo_info 该节点将配置为 Follower
            consul_leader_tag=2
            input_consul_leader_ip
            ;;
        q|Q)
            exit 0
            ;;
        *)
            choose_leader_or_follower
            ;;
    esac
}

# 选择是server端还是client端
function choose_mode() {
    echo -e "\033[31m请输入数字选择consul的安装模式（如需退出请输入q）：\033[0m"
    echo -e "\033[36m[1]\033[32m server模式\033[0m"
    echo -e "\033[36m[2]\033[32m client模式\033[0m"
    read consul_mode
    case ${consul_mode} in
        1)
            echo_info 您选择了 server 模式
            choose_leader_or_follower
            ;;
        2)
            echo_info 您选择了 client 模式
            input_consul_leader_ip
            ;;
        q|Q)
            exit 0
            ;;
        *)
            choose_mode
            ;;
    esac
}

function generate_unit_file() {
    cat >/etc/systemd/system/${unit_file_name} <<EOF
[Unit]
Description="HashiCorp Consul - A service mesh solution"
Documentation=https://www.consul.io
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=${consul_home}/conf/consul.hcl

[Service]
User=${sys_user}
Group=${sys_user}
ExecStart=${consul_home}/bin/consul agent -config-dir=${consul_home}/conf/
ExecReload=${consul_home}/bin/consul reload
ExecStop=${consul_home}/bin/consul leave
KillMode=process
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

function echo_summary() {
    if [ ${consul_mode} -eq 1 ];then
        echo_info consul server 端已部署完毕
        echo_info consul ui访问地址：http://${machine_ip}:8500
    elif [ ${consul_mode} -eq 2 ];then
        echo_info consul client 端已部署完毕
    fi
    echo_info 启动命令：systemctl start consul
}

function main() {
    check_consul
    choose_mode
    check_unzip
    add_user_and_group ${sys_user}

    download_tar_gz ${src_dir} https://releases.hashicorp.com/consul/${consul_version}/consul_${consul_version}_linux_amd64.zip

    echo_info 创建consul目录
    mkdir -p ${consul_home}/{data,conf,bin,snapshot}

    cd ${file_in_the_dir}
    echo_info 解压consul压缩包
    unzip consul_${consul_version}_linux_amd64.zip -d ${consul_home}/bin

    echo_info 配置环境变量
    echo "export PATH=\$PATH:${consul_home}/bin" >> /etc/profile.d/consul.sh
    source /etc/profile

    # 根据节点属性生成配置文件
    get_machine_ip
    echo_info 生成配置文件
    set_consul_config
    if [ ${consul_mode} -eq 1 ];then
        set_server_config
    elif [ ${consul_mode} -eq 2 ];then
        set_client_config
    fi

    echo_info ${consul_home}目录授权
    chown -R ${sys_user}:${sys_user} ${consul_home}
    generate_unit_file

    echo_warning 由于bash特性限制，在本终端使用【consul命令】需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端
    echo_summary
}

main