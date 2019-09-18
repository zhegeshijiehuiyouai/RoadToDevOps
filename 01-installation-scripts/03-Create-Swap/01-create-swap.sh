#!/bin/bash

#脚本测试系统：CentOS7.4
#

SWAPDIR=`pwd`
#设置亲和度
sysctl -w vm.swappiness=30
sed -i 's/vm.swappiness = 0/vm.swappiness = 30/g' /etc/sysctl.conf

#创建一个2G大小的swap
dd if=/dev/zero of=${SWAPDIR}/swap bs=512 count=4194304
mkswap ${SWAPDIR}/swap
chmod 0600 ${SWAPDIR}/swap

#挂载
swapon ${SWAPDIR}/swap
echo "${SWAPDIR}/swap swap swap defaults    0  0" >> /etc/fstab