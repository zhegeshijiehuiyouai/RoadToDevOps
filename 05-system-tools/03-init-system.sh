#!/bin/bash
# 基于CentOS 7.9/Ubuntu 20.04/Ubuntu 22.04

# 全局变量
devops_sysctl_conf=/etc/sysctl.d/99-zz-devops.conf
# 要创建的用户
SUPER_USER_LIST="devops"
NORMAL_USER_LIST="monitor"

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

echo_warning "操作系统：$os    版本：$os_version"

# 判断是否执行过初始化
if [ -f "/opt/._install.lock" ];then
    echo_warning 服务器已执行初始化，如需继续，请删除/opt/._install.lock文件后重新运行
    exit 0
fi

echo_warning 5秒后自动执行，预计需要5分钟，请耐心等待
echo_info 5
sleep 1
echo_info 4
sleep 1
echo_info 3
sleep 1
echo_info 2
sleep 1
echo_info 1
sleep 1
echo_info 开始执行
touch /opt/._install.lock

# 定义最终挂载的名称
partition=/data
# 默认只格式化第一块数据盘
disk=$(lsblk -l | grep disk| egrep -v ".da|nvme0"|awk '{print $1}' | sort | head -1)
if [[ $disk != ''  ]];then
   capacity=$(lsblk -l | grep disk | egrep $disk | awk '{print $4}')
fi

function how_to_deal_with_datadir(){
    read -p "请输入：" -e user_input_how_to_deal_with_datadir
    case $user_input_how_to_deal_with_datadir in
        y|Y)
            echo_info 选择了删除${partition}目录，继续执行初始化操作
            ;;
        n|N)
            echo_warning 用户退出
            exit 0
            ;;
        *)
            how_to_deal_with_datadir
            ;;
    esac
}

# 格式化数据盘
function format_disk(){
    if [[ $disk == ''  ]];then
        echo_warning 未发现数据盘，忽略创建分区和格式化
        return
    fi

    echo_info 格式化数据盘
    if [ -d $partition ];then
        echo_warning "${partition}目录已存在，是否删除，并继续执行(y/n)"
        how_to_deal_with_datadir
    fi
    
    echo_info 请确认信息（5秒后自动执行）：
    echo "硬盘：$disk"
    echo "大小：$capacity"
    echo "文件系统：ext4"
    echo_info 5
    sleep 1
    echo_info 4
    sleep 1
    echo_info 3
    sleep 1
    echo_info 2
    sleep 1
    echo_info 1
    sleep 1

# 自动化完成分区gdisk的交互步骤
    gdisk /dev/$disk <<"_EOF_"
n


 


w
Y
_EOF_

   if [ $? -ne 0 ];then
       echo_error /dev/$disk格式化失败，退出
       exit 1
   fi
   PART_NAME=$(blkid |grep $disk|grep UUID|awk -F ":" '{print $1}')

   echo_info 创建ext4文件系统
   mkfs.ext4 $PART_NAME
   PART_UUID=$(blkid |grep $disk|grep UUID|awk -F '\"' '{print $2}')

   if [ $? -eq 0 ]
   then 
   	mkdir -p $partition
   	echo_info 更新/etc/fstab
   	echo "UUID=$PART_UUID  $partition  ext4     defaults,nofail        0 0" >> /etc/fstab
    # 更新读取/etc/fstab的systemd文件配置
    systemctl daemon-reload
   	mount -a
   	df -h
   else
   	echo_error 文件系统创建失败！
   	exit 1
   fi
}

function install_chrony() {
    rpm -qa | grep "^chrony-" &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装chrony
        yum install -y chrony
        if [ $? -ne 0 ];then
            echo_error chrony安装失败
            exit 1
        fi
        cat > /etc/chrony.conf << _EOF_
server ntp.aliyun.com iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
_EOF_
    fi
    systemctl enable --now chronyd
}

function yum_install_basic_packages() {
    echo_info 安装常用软件包
    if [[ $1 == 'idc' ]];then
        if [[ $os == 'centos' ]];then
            cd /etc/yum.repos.d
            for i in `ls CentOS*`;do mv $i{,.bak};done
            wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
            wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
            yum makecache
            install_chrony
        elif [[ $os == 'ubuntu' ]];then
            sed -i 's|http.*ubuntu|http://mirrors.aliyun.com/ubuntu|g' /etc/apt/sources.list
        elif [[ $os == 'rocky' ]];then
            # 替换为阿里源
            cd /etc/yum.repos.d
            sed -i -e 's|^mirrorlist=|#mirrorlist=|g' -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.tencent.com/rockylinux|g' *.repo
            dnf makecache
        elif [[ $os == 'alma' ]];then
            # 替换为阿里源
            cd /etc/yum.repos.d
            sed -i -e 's|^mirrorlist=|#mirrorlist=|g' -e 's|^# baseurl=https://repo.almalinux.org|baseurl=https://mirrors.tencent.com|g' *.repo
            dnf makecache
        fi
    fi

    if [[ $os == 'centos' ]];then
        yum update -y
        yum install -y vim wget net-tools telnet bash-completion lsof gdisk cloud-utils-growpart
    elif [[ $os == 'ubuntu' ]];then
        apt update -yje
        apt upgrade -y
        apt install -y net-tools
    elif [[ $os == 'rocky' || $os == 'alma' ]];then
        dnf update -y
        dnf install -y vim wget net-tools telnet bash-completion lsof gdisk cloud-utils-growpart tar
    fi
}

function config_profile(){
    echo_info 配置历史命令格式
    mkdir -p /data/logs/history
    chmod 777 /data/logs/history
    cat > /etc/profile.d/devops.sh <<"_EOF_"

### 初始化脚本生成
umask 0022
export TMOUT=300
USER_IP=$(who -u am i 2>/dev/null| awk '{print $NF}'|sed -e 's/[()]//g')
export HISTTIMEFORMAT="${USER_IP} $$ > %F %T [$(whoami)@$(hostname)] "

export HISTORY_FILE=/data/logs/history/${LOGNAME}-$(date '+%Y-%m-%d-%H-%M-%S')-session-$$.log
export PROMPT_COMMAND='{ date +" $(history 1 | { read x cmd; echo "$cmd"; })"; } >> $HISTORY_FILE'
_EOF_

    source /etc/profile.d/devops.sh
}

function adjust_vm_swappiness() {
    echo_info '调整vm.swappiness'
    sysctl -w vm.swappiness=30
    cd /etc/sysctl.d
    sysctl_files=$(ls /etc/sysctl.d)
    # 标志位，是否有这个配置，没有的话需要新增
    change_tag=0
    for file in $sysctl_files;do
        grep 'vm.swappiness' $file &> /dev/null
        if [ $? -eq 0 ];then
            change_tag=1
            sed -i 's/vm.swappiness.*/vm.swappiness = 30/g' $file
        fi
    done
    # 配置中没有vm.swappiness，需要新增
    if [ $change_tag -eq 0 ];then
        if [ ! -f $devops_sysctl_conf ];then
            echo '# 该配置文件由初始化脚本生成' > $devops_sysctl_conf
        fi
        echo 'vm.swappiness = 30' >> $devops_sysctl_conf
    fi
}

function create_swapfile() {
    # 已经有swap了的不创建
    swap_size=$(free | grep Swap | awk '{print $2}')
    if [ $swap_size -ne 0 ];then
        adjust_vm_swappiness
        return 0
    fi
    # 内存大于等于16G的不创建（给出警告，人工斟酌是否需要创建）
    mem_size=$(free -g | grep Mem | awk '{print $2}')
    # 16G的只能查到15
    if [ $mem_size -ge 15 ];then
        echo_warning 服务器内存大于等于16G，跳过Swap创建，如需Swap请手动创建
        return 1
    fi
   	echo_info 创建swap文件，大小2G
    dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
   	echo_info 更新/etc/fstab
   	echo "/swapfile  swap  swap     defaults,nofail        0 0" >> /etc/fstab
    adjust_vm_swappiness
}

function config_system_parameter(){
    echo_info 调整文件最大句柄数量

    sed -i 's|^\* hard nofile|#* hard nofile|' /etc/security/limits.conf
    sed -i 's|^\* soft nofile|#* soft nofile|' /etc/security/limits.conf
    sed -i 's|^root hard nofile|#root hard nofile|' /etc/security/limits.conf
    sed -i 's|^root soft nofile|#root soft nofile|' /etc/security/limits.conf

    cat >>/etc/security/limits.conf<<"_EOF_"
### Max open file limit 
* soft nofile 15000000
* hard nofile 15000000
* soft noproc 15000000
* hard noproc 15000000
_EOF_

    if [[ $os == 'centos' ]];then
        sed -i 's|^\*          soft    nproc     4096|#*          soft    nproc     4096|' /etc/security/limits.d/20-nproc.conf
    fi

    cat >>/etc/security/limits.d/20-nproc.conf<<"_EOF_"
### Max open file limit
*          soft    nproc     unlimited
_EOF_

    if [[ $os == 'centos' || $os == 'ubuntu' ]];then
        cat >>'/etc/systemd/system.conf' <<"_EOF_"
DefaultTimeoutStartSec=30s
DefaultTimeoutStopSec=30s
DefaultRestartSec=5s
DefaultLimitCORE=infinity
DefaultLimitNOFILE=infinity
DefaultLimitNPROC=infinity
_EOF_
    elif [[ $os == 'rocky' || $os == 'alma' ]];then
        cat >>'/etc/systemd/system.conf' <<"_EOF_"
DefaultTimeoutStartSec=30s
DefaultTimeoutStopSec=30s
DefaultRestartSec=5s
DefaultLimitNOFILE=18446744073709551615
DefaultLimitNPROC=18446744073709551615
_EOF_
    fi

    systemctl daemon-reload

    echo_info 调整内核参数
cat > /etc/sysctl.conf <<"_EOF_"
# sysctl settings are defined through files in
# /usr/lib/sysctl.d/, /run/sysctl.d/, and /etc/sysctl.d/.
#
# Vendors settings live in /usr/lib/sysctl.d/.
# To override a whole file, create a new file with the same in
# /etc/sysctl.d/ and put new settings there. To override
# only specific settings, add a file with a lexically later
# name in /etc/sysctl.d/ and put new settings there.
#
# For more information, see sysctl.conf(5) and sysctl.d(5).
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

net.ipv4.neigh.default.gc_stale_time=120

# see details in https://help.aliyun.com/knowledge_detail/39428.html
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce=2
net.ipv4.conf.all.arp_announce=2

# see details in https://help.aliyun.com/knowledge_detail/41334.html
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_synack_retries = 2
kernel.sysrq=1

# single process
fs.nr_open = 20000000
# system file max
fs.file-max = 50000000

# inotify
fs.inotify.max_queued_events=327679
fs.inotify.max_user_watches=30000000

# elasticsearch required
vm.max_map_count = 262184

# avoid kernel bug: task blocked for more than 120 seconds
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
_EOF_
    sysctl -p &> /dev/null
}

function config_firewalld(){
    if [[ $os == 'centos' || $os == 'rocky' || $os == 'alma' ]];then
        echo_info 关闭SELINUX
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        setenforce 0
        echo_info 关闭不必要的服务
        systemctl disable --now postfix
        systemctl disable --now rpcbind 
        systemctl disable --now rpcbind.socket
        echo_info 关闭防火墙
        systemctl stop firewalld &> /dev/null
        systemctl disable firewalld &> /dev/null
    elif [[ $os == 'ubuntu' ]];then
        echo_info 关闭AppArmor
        systemctl stop apparmor &> /dev/null
        systemctl disable apparmor &> /dev/null
        echo_info 关闭防火墙
        systemctl stop ufw &> /dev/null
        systemctl disable ufw &> /dev/null
    fi
}

function config_sshd(){
    echo_info 禁止定时任务向root发送邮件
    sed -i 's/^MAILTO=root/MAILTO=""/' /etc/crontab
    echo_info 优化sshd配置
    sed -i 's/^UseDNS/#UseDNS/' /etc/ssh/sshd_config
    sed -i 's/^AddressFamily/#AddressFamily/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin/#PermitRootLogin/' /etc/ssh/sshd_config
    sed -i 's/^SyslogFacility/#SyslogFacility/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication/#PasswordAuthentication/' /etc/ssh/sshd_config
    sed -i 's/^ClientAliveCountMax/#ClientAliveCountMax/' /etc/ssh/sshd_config
    sed -i 's/^ClientAliveInterval/#ClientAliveInterval/' /etc/ssh/sshd_config
    sed -i 's/^MaxAuthTries/#MaxAuthTries/' /etc/ssh/sshd_config
    sed -i 's/^X11Forwarding/#X11Forwarding/' /etc/ssh/sshd_config
    sed -i 's/^PermitEmptyPasswords/#PermitEmptyPasswords/' /etc/ssh/sshd_config

    cat >>/etc/ssh/sshd_config<<"_EOF_"

### sshd hardening
UseDNS no
AddressFamily inet
PermitRootLogin no
SyslogFacility AUTHPRIV
PasswordAuthentication yes
ClientAliveInterval 600
ClientAliveCountMax 2
MaxAuthTries 3
X11Forwarding no
PermitEmptyPasswords no

_EOF_

    if [[ "$os" == "ubuntu" && "$os_version" == "24.04" ]]; then
        systemctl daemon-reload
        systemctl restart ssh.socket
    else
        systemctl restart sshd
    fi
    
    cat >>/etc/motd<<"_EOF_"

###############################################################
#                  This is a private server!                  #
#       All connections are monitored and recorded.           #
#  Disconnect IMMEDIATELY if you are not an authorized user!  #
###############################################################
_EOF_
}

function config_vi(){
    echo_info 优化vi

    if [ -L /usr/bin/vi ];then
            echo_info 配置visudo语法高亮
            echo_info 已设置vi软链接 $(ls -lh /usr/bin/vi | awk '{for (i=9;i<=NF;i++)printf("%s ", $i);print ""}')
    elif [ -f /usr/bin/vim ];then
        echo_info 配置visudo语法高亮
        mv -f /usr/bin/vi /usr/bin/vi_bak
        ln -s /usr/bin/vim /usr/bin/vi
    fi
}

function create_users(){
    echo_info 创建系统账号
    for i in ${SUPER_USER_LIST}
    do
        id -u ${i} &> /dev/null
        if [ $? -ne 0 ];then
            useradd -m ${i} -d /home/${i}/
        fi
        # vim
        cat >> /home/${i}/.vimrc <<"_EOF_"
set paste
set fileencoding=utf-8
set termencoding=utf-8
set encoding=utf-8
_EOF_
        chown ${i}:${i} /home/${i}/.vimrc
        chmod 600 /home/${i}/.vimrc
        # alias
        cat >>/home/${i}/.bashrc<<"_EOF_"
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias systemctl='sudo systemctl'
_EOF_
        if [[ $os == 'ubuntu' ]];then
            cat >>/home/${i}/.bashrc<<"_EOF_"
PS1='\[\e]0;\u@\h: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
_EOF_
        fi
	done

    for i in ${NORMAL_USER_LIST}
    do
        useradd -m ${i} -d /home/${i}/
        # vim
        cat >> /home/${i}/.vimrc <<"_EOF_"
set paste
set fileencoding=utf-8
set termencoding=utf-8
set encoding=utf-8
_EOF_
        chown ${i}:${i} /home/${i}/.vimrc
        chmod 600 /home/${i}/.vimrc
        # alias
        cat >>/home/${i}/.bashrc<<"_EOF_"
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
_EOF_
        if [[ $os == 'ubuntu' ]];then
            cat >>/home/${i}/.bashrc<<"_EOF_"
PS1='\[\e]0;\u@\h: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
_EOF_
        fi
	done

    # root配置
    if [[ $os == 'ubuntu' ]];then
        cat >>/root/.bashrc<<"_EOF_"
PS1='\[\e]0;\u@\h: \w\a\]\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
_EOF_
        rm -f /usr/bin/sh
        ln -s /usr/bin/bash /usr/bin/sh

        cd /etc/update-motd.d/
        ls | grep -v 50-landscape-sysinfo | xargs rm -f
    fi
    
    # root vim配置
    cat >> /root/.vimrc <<"_EOF_"
set paste
set fileencoding=utf-8
set termencoding=utf-8
set encoding=utf-8
_EOF_
    chmod 600 /root/.vimrc
	mkdir -p /home/devops/.ssh && chown -R devops:devops /home/devops/.ssh && chmod 700 /home/devops/.ssh
}

function config_privillege(){
    echo_info 配置账号权限
    chmod 600 /home/devops/.ssh/authorized_keys
    chmod 700 /home/devops/.ssh
    chown -R devops:devops /home/devops
    mkdir -p /data/logs/

    cat >>/opt/log_clean.sh<<"_EOF_"
#!/bin/bash

#delete logs
find /data/logs -maxdepth 3 -mtime +7 -name "*20*.log" ! -path "*history*" -exec rm -f {} \;

#delete system log
find /var/log -maxdepth 3 -mtime +7 -name "*20*" -exec rm -f {} \;

# 删除历史命令记录
find /data/logs/history -mtime +90 | xargs rm -f

#delete logs for tomcat
find /home/devops/*/logs -maxdepth 3 -mtime +0 -name "*20*.log" -exec rm -f {} \;
find /home/devops/*/data/logs -maxdepth 3 -mtime +0 -name "*20*.log" -exec rm -f {} \;

_EOF_
    chmod +x /opt/log_clean.sh
    ln -s /opt/log_clean.sh /etc/cron.daily/
    chown -R devops:devops /data

    for i in ${SUPER_USER_LIST}
    do
        if ! cat /etc/sudoers | grep $i &> /dev/null;then
            echo "$i ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
        fi
    done
}

function config_hardening(){
    echo_info 安全加固
    if [[ $os == 'centos' || $os == 'rocky' || $os == 'alma' ]];then
        sed -i 's/account[[:space:]]\+required[[:space:]]\+pam_unix.so.*/&  no_pass_expiry/' /etc/pam.d/system-auth
        sed -i 's/password[[:space:]]\+sufficient[[:space:]]\+pam_unix.so.*/&  remember=3  no_pass_expiry/' /etc/pam.d/system-auth
        sed -i 's/password[[:space:]]\+sufficient[[:space:]]\+pam_unix.so.*/&  remember=3  no_pass_expiry/' /etc/pam.d/password-auth
        sed -i 's/account[[:space:]]\+required[[:space:]]\+pam_unix.so.*/&  no_pass_expiry/' /etc/pam.d/password-auth

        sed -i 's/^minclass.*/# &/' /etc/security/pwquality.conf
        sed -i 's/^minlen.*/# &/' /etc/security/pwquality.conf
    elif [[ $os == 'ubuntu' ]];then
        latest_ubuntu_version=$(echo -e "${os_version}\n22.04" | sort -V -r | head -1)
        # 22.04及之前的版本使用下面的方法
        if [[ $latest_ubuntu_version == 22.04 ]];then
            apt -y install libpam-cracklib
            sed -i 's/password[[:space:]]\+requisite[[:space:]]\+pam_cracklib.so.*/password        requisite                       pam_cracklib.so retry=3 minlen=9 difok=3 dcredit=-1 lcredit=-1 ocredit=-1 ucredit=-1/' /etc/pam.d/common-password
        # 24.04及之后
        else
            apt -y install libpam-pwquality
            sed -i 's/password[[:space:]]\+requisite[[:space:]]\+pam_pwquality.so.*/password        requisite                       pam_pwquality.so retry=3 minlen=9 difok=3 dcredit=-1 lcredit=-1 ocredit=-1 ucredit=-1/' /etc/pam.d/common-password
        fi
        # 不能和最近使用过的3个密码一样
        sed -i 's/password[[:space:]]\+[success=1[[:space:]]\+default=ignore][[:space:]]\+pam_unix.so.*/& remember=3/' /etc/pam.d/common-password
    fi
    sed -i 's/^PASS_MIN_LEN.*/PASS_MIN_LEN 9/' /etc/login.defs
    sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 7/' /etc/login.defs
    sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE 30/' /etc/login.defs
    cat >>/etc/security/pwquality.conf<<"_EOF_"
minlen = 9
difok = 3
dcredit = -1
lcredit = -1
ocredit = -1
ucredit = -1
_EOF_
}


######################## 初始化操作 ###########################
yum_install_basic_packages
create_swapfile
format_disk
config_profile
config_system_parameter
config_firewalld

config_vi
create_users

config_privillege

config_hardening
config_sshd

######################## 重启服务器 ###########################
echo_warning 服务器初始化已完毕，即将重启
echo_warning 5秒后自动重启，请耐心等待）：
echo_info 5
sleep 1
echo_info 4
sleep 1
echo_info 3
sleep 1
echo_info 2
sleep 1
echo_info 1
sleep 1
echo_info 开始重启
init 6
