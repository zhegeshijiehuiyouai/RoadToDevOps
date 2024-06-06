#!/bin/bash
# rsync使用的认证用户和密码，不是指系统用户
rsyncd_user=rsyncd
rsyncd_password=rsyncdpass
rsyncd_port=873

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

function check_rsync_server() {
    rsync --version &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装rsync包
        if [[ $os == "centos" ]];then
            yum install -y rsync
        elif [[ $os == "ubuntu" ]];then
            apt install -y rsync
        elif [[ $os == "rocky" ]];then
            dnf install -y rsync
        fi
    fi
    
    ps -ef | grep rsync | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到 rsync 服务正在运行中，退出
        exit 1
    fi
}

function get_machine_ip() {
    function input_machine_ip_fun() {
        read -e input_machine_ip
        machine_ip=${input_machine_ip}
        if [[ ! $machine_ip =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
            echo_error 错误的ip格式，退出
            exit 2
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
        check_share_dir_is_legal_count=0

        if [[ "${share_dirs[0]}" == "" ]];then
            echo_error 没有输入任何内容
            exit 3
        fi
        for i in ${share_dirs[@]};do
            if [ ! -d ${i} ];then
                echo_error 未检测到目录 ${i}，请确认输入是否正确
                exit 4
            fi
            # 下面这个变量用于模块名
            formated_share_dir[${check_share_dir_is_legal_count}]=$(echo ${i} | sed 's#/#_#g' | sed 's/^.//' | sed 's/_$//')
            let check_share_dir_is_legal_count++
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

function generate_rsyncd_conf() {
    function generate_share_dir_conf() {
        rm -f /tmp/.generate_share_dir_conf_tempfile
        formated_share_dir_count=0
        for i in ${share_dirs[@]};do
            cat >> /tmp/.generate_share_dir_conf_tempfile << EOF
#--------------------- START ------------------------
#共享模块名称
[${formated_share_dir[${formated_share_dir_count}]}]
#源目录的实际路径
path = ${i}
#提示信息，无所谓的，不写也行
comment = This is ${i} at ${machine_ip}
#有读写的权限，若改为“yes”，则表示为只读权限。
read only = no
#同步时不再压缩的文件类型。
# dont compress   = *.gz *.tgz *.zip *.z *.Z *.rpm *.deb *.bz2
#授权账户
auth users = ${rsyncd_user}
#存放账户信息的数据文件。格式为 ->  用户名:密码
secrets file = /etc/rsync.d/rsyncd.secrets
hosts allow = *
#允许访问的ip
# hosts allow = 172.168.1.45
#默认禁止所有ip访问
# hosts deny = 0.0.0.0/0
#--------------------- STOP ------------------------

EOF
            let formated_share_dir_count++
        done
    }

    echo_info 调整 rsyncd 配置文件
    get_machine_ip
    [ -d /etc/rsync.d ] || mkdir -p /etc/rsync.d
    cat > /etc/rsyncd.conf << EOF
#启用匿名用户
uid = root
gid = root
#禁锢在源目录
use chroot = yes
#监听地址
address = ${machine_ip}
#监听端口
port ${rsyncd_port}
#最大并发连接数，以保护服务器，超过限制的连接数请求时，将被暂时限制。默为0(没有限制)
# max connections = 4
#定义服务器信息
motd file = /etc/rsync.d/rsyncd.motd
#日志文件位置
log file = /var/log/rsyncd.log
#存放进程ID的文件位置
pid file = /var/run/rsyncd.pid
#用来支持max connections 的锁文件，默认值是/var/run/rsyncd.lock
# lock file = /var/run/rsyncd.lock
#允许访问的客户端地址，可以省略不写，则表示允许任意地址访问
# hosts allow = 192.168.1.0/24
# exclude = lost+found/    
# transfer logging = yes
# log format = %t %a %m %f %b
# syslog facility = local3
timeout = 300
# ignore nonreadable = yes
dont compress   = *.gz *.tgz *.zip *.z *.Z *.rpm *.deb *.bz2

EOF
    cat > /etc/rsync.d/rsyncd.motd << EOF
############################################################################
    Welcome to use the mike.org.cn rsync services!
    Script file from https://github.com/zhegeshijiehuiyouai/RoadToDevOps
############################################################################
EOF
    echo "${rsyncd_user}:${rsyncd_password}" > /etc/rsync.d/rsyncd.secrets
    chmod 600 /etc/rsync.d/rsyncd.secrets
    generate_share_dir_conf
    sed -i '/^$/ r /tmp/.generate_share_dir_conf_tempfile' /etc/rsyncd.conf
}

function echo_summary() {
    echo_info rsyncd 已配置完毕并成功启动！
    echo_info 已配置的共享模块名称：
    for i in ${formated_share_dir[@]};do
        echo $i
    done
    echo_info 验证 rsyncd 命令（本机执行，密码：${rsyncd_password}）：
    echo -e "\033[45mrsync --list-only ${rsyncd_user}@${machine_ip}::${formated_share_dir[0]}\033[0m"
    echo_info 生产环境客户端同步命令：
    echo -e "\033[45m[ -d /etc/rsync.d ] || mkdir -p /etc/rsync.d\033[0m"
    echo -e "\033[45mecho \""${rsyncd_password}"\" > /etc/rsync.d/rsync.password\033[0m"
    echo -e "\033[45mchmod 600 /etc/rsync.d/rsync.password\033[0m"
    echo -e "\033[45mrsync -avz --port=${rsyncd_port} --delete --password-file=/etc/rsync.d/rsync.password /path/to/sorce/dir/ ${rsyncd_user}@${machine_ip}::${formated_share_dir[0]}\033[0m"
}

function main() {
    check_rsync_server
    input_share_dir
    generate_rsyncd_conf
    # 启动服务
    if [[ $os == "centos" ]];then
        systemctl start rsyncd
        if [ $? -eq 0 ];then
            echo_info 启动 rysncd 服务：systemctl start rsyncd
            echo_summary
        else
            echo_error rsyncd 启动失败，请检查！
            exit 5
        fi
    elif [[ $os == "ubuntu" ]];then
        systemctl start rsync
        if [ $? -eq 0 ];then
            echo_info 启动 rsyncd 服务：systemctl start rsync
            echo_summary
        else
            echo_error rsyncd 启动失败，请检查！
            exit 5
        fi
    elif [[ $os == "rocky" ]];then
        # rocky linux中没有rsyncd服务了，要自己创建
        cat > /etc/sysconfig/rsyncd << _EOF_
OPTIONS=""
_EOF_
        cat > /etc/systemd/system/rsyncd.service << _EOF_
[Unit]
Description=fast remote file copy program daemon
ConditionPathExists=/etc/rsyncd.conf

[Service]
EnvironmentFile=/etc/sysconfig/rsyncd
ExecStart=/usr/bin/rsync --daemon --no-detach "\$OPTIONS"

[Install]
WantedBy=multi-user.target
_EOF_
        systemctl daemon-reload
        systemctl start rsyncd
        if [ $? -eq 0 ];then
            echo_info 启动 rysncd 服务：systemctl start rsyncd
            echo_summary
        else
            echo_error rsyncd 启动失败，请检查！
            exit 5
        fi
    fi
}

main