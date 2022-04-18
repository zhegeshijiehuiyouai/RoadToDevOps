#!/bin/bash
# only use in centos7
partition=/data                # 定义最终挂载的名称
vgname=vgdata                      # 定义逻辑卷组的名称
lvmname=lvmdata                     # 定义逻辑卷的名称
code='vdb'   # 根据分区的实际情况修改

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

echo_info 检测lvm2
yum install -y lvm2

if [ -d $partition ];then
	echo_error ${partition}目录已存在，退出
	exit 1
fi

disk=
for i in $code  
do
lsblk | grep $i | grep disk &> /dev/null
if [ $? -ne 0 ];then
    echo_error 为发现硬盘/dev/$i，退出
	exit 2
fi
# 这里自动化完成了所有分区fdisk苦逼的交互步骤
fdisk /dev/$i << EOF          
n
p
1
 

t
8e
w
EOF
disk="$disk /dev/${i}1" # 将所有分区拼起来
done

echo_info 即将使用这些磁盘创建lvm：$disk

echo_info 创建pv
pvcreate $disk
echo_info 创建vg
vgcreate $vgname $disk
lvcreate -l 100%VG -n $lvmname $vgname
echo_info 创建lv

echo_info 创建xfs文件系统
mkfs.xfs /dev/$vgname/$lvmname
if [ $? == 0 ]
then 
	mkdir -p $partition
	echo_info 更新/etc/fstab
	echo "/dev/$vgname/$lvmname  $partition  xfs     defaults        0 0" >> /etc/fstab
	mount -a
	echo_info lvm创建成功\
	echo_info lvm文件系统磁盘空间使用情况：
	df -h
else
	echo_error lvm创建失败！
	exit 1
fi
