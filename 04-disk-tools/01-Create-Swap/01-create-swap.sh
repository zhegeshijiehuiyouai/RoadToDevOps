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

SWAPDIR=`pwd`

echo_info 设置swap亲和度为30
sysctl -w vm.swappiness=30
sed -i 's/vm.swappiness = 0/vm.swappiness = 30/g' /etc/sysctl.conf

echo_info 创建一个2G大小的swap文件：${SWAPDIR}/swap
dd if=/dev/zero of=${SWAPDIR}/swap bs=512 count=4194304
mkswap ${SWAPDIR}/swap
chmod 0600 ${SWAPDIR}/swap

echo_info 挂载swap
swapon ${SWAPDIR}/swap
echo "${SWAPDIR}/swap swap swap defaults    0  0" >> /etc/fstab

echo_info swap已创建成功
free -h