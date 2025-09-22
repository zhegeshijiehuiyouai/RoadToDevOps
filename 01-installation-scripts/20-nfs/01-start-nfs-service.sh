#!/bin/bash

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
	echo_error 不支持的操作系统
	exit 99
fi

function check_nfs_service() {
    ps -ef | grep -E "\[nfsd\]" | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到 nfs 服务正在运行中，退出
        exit 1
    fi
}

function start_nfs() {
    if [[ ! -f /usr/sbin/nfsstat ]];then
        echo_info 安装 nfs
        if [[ $os == "centos" ]];then
            yum install -y nfs-utils
        elif [[ $os == "ubuntu" ]];then
            apt install -y nfs-common nfs-kernel-server
        elif [[ $os == "rocky" || $os == 'alma' ]];then
            dnf install -y nfs-utils
        fi
    fi

    if [[ $os == "centos" ]];then
        systemctl start rpcbind
        systemctl start nfs
    elif [[ $os == "ubuntu" ]];then
        systemctl start nfs-kernel-server
    elif [[ $os == "rocky" || $os == 'alma' ]];then
        systemctl start rpcbind
        systemctl start nfs-server
    fi
}

function get_machine_ip() {
    machine_ip=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
}

function input_share_dir() {
    function accept_share_dir() {
        read -e share_dir

        if [ "" != "$share_dir" ];then
            # 进入此处，表示用户输入了值，需要重置空行标志位
            dir_null_flag=0
            share_dirs[$dir_num]=$share_dir
            let dir_num++
            accept_share_dir
        else
            if [ $dir_null_flag -eq 1 ];then
                # 第二次输入空行，会进入到此
                return
            else
                # 第一次输入空行，会进入到此，设置flag
                dir_null_flag=1
                accept_share_dir
            fi
        fi
    }
    function check_share_dir_is_legal() {
        if [[ "${share_dirs[0]}" == "" ]];then
            echo_error 没有输入任何内容
            exit 3
        fi
        for i in ${share_dirs[@]};do
            if [ ! -d ${i} ];then
                echo_error 未检测到目录 ${i}，请确认输入是否正确
                exit 4
            fi
        done
    }

    # 接收目录的数组的下标
    dir_num=0
    # 该标志位用户是否输入了空行，输入两次空行则表示没有输入了，继续下一步
    dir_null_flag=0
    echo_info 请输入要共享的目录，如有多个，请回车后继续输入，连输两次空行继续下一步部署操作：
    # read -p $'请输入要共享的目录: \n' -e share_dir
    accept_share_dir
    check_share_dir_is_legal
}

function generate_nfs_conf() {
    echo_info 配置nfs
    get_machine_ip
    net_ip=$(echo ${machine_ip} | sed 's/[0-9]*$/0/')
    net_mask=$(ip a | grep ${machine_ip} | awk '{print $2}' | awk -F "/" '{print $2}')
    if [ $? -ne 0 ];then
        echo_info 请手动输入子网掩码（24、32这种格式）
        read -e INPUT_NET_MASK
        if [[ ! ${INPUT_NET_MASK} =~ ^[0-9] ]];then
            echo_error 错误的子网掩码格式，退出
            exit 2
        fi
        net_mask=${INPUT_NET_MASK}
    fi
    input_share_dir
    :>/etc/exports
    for i in ${share_dirs[@]};do
        cat >> /etc/exports <<EOF
${i} ${net_ip}/${net_mask}(rw,sync,no_wdelay,no_root_squash,no_subtree_check)
EOF
    # rw：该主机对该共享目录有读写权限
    # ro：该主机对该共享目录有只读权限
    # sync：将数据同步写入内存缓冲区与磁盘中，效率低，但可以保证数据的一致性
    # async：将数据先保存在内存缓冲区中，必要时才写入磁盘
    # wdelay：如果多个用户要写入NFS目录，则归组写入，这样可以提高效率（默认设置）
    # no_wdelay：如果多个用户要写入NFS目录，则立即写入，【当使用async时，无需此设置】
    # all_squash：客户机上的任何用户访问该共享目录时都映射成匿名用户（nfsnobody）
    # no_root_squash：客户机用root访问该共享文件夹时，不映射root用户为匿名用户，即具有共享文件夹服务器的root权限
    # root_squash：客户机用root用户访问该共享文件夹时，将root用户映射成匿名用户
    # subtree_check：若输出目录是一个子目录，则nfs服务器将检查其父目录的权限(默认设置)；
    # no_subtree_check：即使输出目录是一个子目录，nfs服务器也不检查其父目录的权限，这样可以提高效率；
    # secure：限制客户端只能从小于1024的TCP/IP端口连接NFS服务器（默认设置）。
    # insecure：允许客户端从大于1024的TCP/IP端口连接NFS服务器。
    
    done
    echo_info 共享目录
    exportfs -ravf
}

function echo_summary() {
    echo_info nfs已配置并启动完毕，相关使用命令如下：
    echo 客户端挂载nfs命令：
    echo -e "\033[45m# nfs客户端并发数调优\033[0m"
    echo -e "\033[45mecho \"options sunrpc tcp_slot_table_entries=128\" >> /etc/modprobe.d/sunrpc.conf\033[0m"
    echo -e "\033[45mecho \"options sunrpc tcp_max_slot_table_entries=128\" >>  /etc/modprobe.d/sunrpc.conf\033[0m"
    echo -e "\033[45mmodprobe sunrpc\033[0m"
    echo -e "\033[45msysctl -w sunrpc.tcp_slot_table_entries=128\033[0m"
    echo -e "\033[45mmount -t nfs -o soft,intr,timeo=5,retry=5 ${machine_ip}:${share_dirs[0]} MOUNT_POINT\033[0m"
    # soft：(默认值)当服务器端失去响应后，访问其上文件的应用程序将收到一个错误信号而不是被挂起。
    # timeo：与服务器断开后，尝试连接服务器的间隔时间，默认600（60秒）
    # intr：允许通知中断一个NFS调用。当服务器没有应答需要放弃的时候有用处
    # retry：失败后重试次数

    echo 服务端取消nfs共享目录命令：
    echo -e "\033[45mexportfs -u ${net_ip}/${net_mask}:${share_dirs[0]}\033[0m"
    echo 停止nfs命令：
    if [[ $os == "centos" ]];then
        echo -e "\033[45msystemctl stop nfs\033[0m"
    elif [[ $os == "ubuntu" ]];then
        echo -e "\033[45msystemctl stop nfs-kernel-server\033[0m"
    elif [[ $os == "rocky" || $os == 'alma' ]];then
        echo -e "\033[45msystemctl stop nfs-server\033[0m"
    fi
    echo -e "\033[45msystemctl stop rpcbind\033[0m"
}

function main() {
    check_nfs_service
    start_nfs
    generate_nfs_conf
    echo_summary
}


main