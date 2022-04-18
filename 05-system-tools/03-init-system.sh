#!/bin/bash
# 本脚本适用于CentOS7



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

function yum_install_basic_packages() {
    echo_info 安装常用软件包
    yum install -y vim net-tools telnet bash-completion glances # wget需要提前安装，故此处注释掉
}

echo_info 检测是否能连接到互联网
ping -c 1 -w 1 114.114.114.114 &> /dev/null
if [ $? -eq 0 ];then
    echo_info 已连接到互联网，将执行有网络模式下的优化
    online=0

    echo_info 检测DNS服务器是否配置
    grep -E "^nameserver" /etc/resolv.conf &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 添加DNS服务器配置
        echo "nameserver 61.139.2.69" >> /etc/resolv.conf
        echo "nameserver 114.114.114.114" >> /etc/resolv.conf
    else
        echo_info 系统已配置DNS服务器
    fi

    echo_info 配置阿里云yum仓库
    yum install -y wget
    rm -rf /etc/yum.repos.d/*
    wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
    wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo
    yum_install_basic_packages
else
    echo_warning 无法连接到互联网，将执行无网络模式下的优化
    online=1
    
    echo_info 检测是否有离线yum仓库
    timeout 7 yum makecache &> /dev/null
    if [ $? -eq 0 ];then
        echo_info 离线yum仓库可用
        off_yum=0
        yum_install_basic_packages
    else
        echo_warning 离线yum仓库不可用
        off_yum=1
    fi
fi

echo_info 配置hosts文件，解封github
cat >> /etc/hosts <<EOF

# generate by https://github.com/zhegeshijiehuiyouai/RoadToDevOps
13.229.188.59   github.com
52.74.223.119   www.github.com
199.232.69.194  github.global.ssl.fastly.net
185.199.108.153 assets-cdn.github.com
185.199.108.133 user-images.githubusercontent.com
EOF

echo_info 配置历史命令格式
cat > /etc/profile.d/init.sh << EOF
# 历史命令格式
USER_IP=\$(who -u am i 2>/dev/null| awk '{print \$NF}'|sed -e 's/[()]//g')
export HISTTIMEFORMAT="\${USER_IP} > %F %T [\$(whoami)@\$(hostname)] "
EOF

echo_info 调整文件最大句柄数量
grep -E "root.*soft.*nofile" /etc/security/limits.conf &> /dev/null
if [ $? -ne 0 ];then
    sed -i '/End of file/a root soft nofile 65536' /etc/security/limits.conf
fi
grep -E "root.*hard.*nofile" /etc/security/limits.conf &> /dev/null
if [ $? -ne 0 ];then
    sed -i '/root.*soft.*nofile/a root hard nofile 65536' /etc/security/limits.conf
fi

echo_info 内核参数调整
cat > /etc/sysctl.conf << EOF
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

net.ipv4.ip_forward = 1
fs.file-max = 6815744
EOF
sysctl -p &> /dev/null

echo_info 关闭防火墙，如有需求请使用iptables规则，不要使用firewalld
systemctl stop firewalld &> /dev/null
systemctl disable firewalld &> /dev/null
echo_info 关闭selinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
setenforce 0

echo_info 调整sshd配置
grep -E "^UseDNS" /etc/ssh/sshd_config &> /dev/null
if [ $? -eq 0 ];then
    sed -i 's/UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
else
    grep -E "^#UseDNS" /etc/ssh/sshd_config &> /dev/null
    if [ $? -eq 0 ];then
        sed -i 's/#UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
    else
        echo "UseDNS no" >> /etc/ssh/sshd_config
    fi
fi
systemctl restart sshd

echo_info 配置timezone
echo "Asia/Shanghai" > /etc/timezone

echo_info 禁止定时任务向root发送邮件
sed -i 's/^MAILTO=root/MAILTO=""/' /etc/crontab

echo_info 调整命令提示符显示格式
echo "PS1='\[\e]0;\u@\h: \w\a\]\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\\$ '" > /etc/profile.d/PS.sh

if [ -L /usr/bin/vi ];then
        echo_info 配置visudo语法高亮
        echo_info 已设置vi软链接 $(ls -lh /usr/bin/vi | awk '{for (i=9;i<=NF;i++)printf("%s ", $i);print ""}')
elif [ -f /usr/bin/vim ];then
    echo_info 配置visudo语法高亮
    mv -f /usr/bin/vi /usr/bin/vi_bak
    ln -s /usr/bin/vim /usr/bin/vi
fi

echo_warning 各系统参数已调整完毕，请执行 source /etc/profile 刷新环境变量；或者重新打开一个终端，在新终端里操作