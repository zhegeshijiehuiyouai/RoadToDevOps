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

echo_info 配置历史命令格式
cat > /etc/profile.d/init.sh << EOF
# 历史命令格式
USER_IP=\$(who -u am i 2>/dev/null| awk '{print \$NF}'|sed -e 's/[()]//g')
export HISTTIMEFORMAT="\${USER_IP} > %F %T [\$(whoami)@\$(hostname)] "
EOF

echo_info 调整文件最大句柄数量
grep -E "root.*soft.*nofile" /etc/security/limits.conf &> /dev/null
if [ $? -ne 0 ];then
    sed -i '/End of file/a root soft nofile 65535' /etc/security/limits.conf
fi
grep -E "root.*hard.*nofile" /etc/security/limits.conf &> /dev/null
if [ $? -ne 0 ];then
    sed -i '/root.*soft.*nofile/a root hard nofile 65535' /etc/security/limits.conf
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
systemctl stop firewalld
systemctl disable firewalld
echo_info 关闭selinux
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

echo_warning 各系统参数已调整完毕，请执行 source /etc/profile 刷新环境变量；或者重新打开一个终端，在新终端里操作