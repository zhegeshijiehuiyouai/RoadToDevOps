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

echo_info 添加镜像源
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm

echo_info 安装最新内核RPM包
yum --enablerepo=elrepo-kernel install kernel-ml -y


echo_info 设置内核
# 按照版本号对kernel进行排序
newest_kernel=$(egrep ^menuentry /etc/grub2.cfg | cut -f 2 -d \' | awk -F "(" '{print $2}' | awk -F ")" '{print $1}' | sort -V | tail -1)
newest_kernel_id=$(egrep ^menuentry /etc/grub2.cfg | cut -f 2 -d \' | cat -n | grep ${newest_kernel} | awk '{print $1}' | head -1)
newest_kernel_id=$((newest_kernel_id - 1))
grub2-set-default ${newest_kernel_id}


echo_info 开启BBR算法
echo 'net.core.default_qdisc=fq' > /etc/sysctl.d/bbr.conf
echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.d/bbr.conf

echo_info 内核参数优化
cat > /etc/sysctl.d/bbr.conf <<EOF
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.ip_forward=1
net.ipv4.tcp_syncookies=1

net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1
EOF

sysctl -p

echo_info "是否重启服务器 [Y/n]"
read is_reboot
case ${is_reboot} in
    y|Y)
        reboot
        ;;
    *)
        exit 0
        ;;
esac
