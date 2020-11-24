#!/bin/bash
# only use in centos7
partition=/data                # 定义最终挂载的名称
vgname=vgdata                      # 定义逻辑卷组的名称
lvmname=lvmdata                     # 定义逻辑卷的名称
code='vdb'   # 根据分区的实际情况修改

if [ -d $partition ];then
	echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m${partition}目录已存在，退出\033[0m"
	exit 1
fi

disk=
for i in $code  
do
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

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m即将使用这些磁盘创建lvm：$disk\033[0m"

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m创建pv\033[0m"
pvcreate $disk
echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m创建vg\033[0m"
vgcreate $vgname $disk
lvcreate -l 100%VG -n $lvmname $vgname
echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m创建lv\033[0m"

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m创建xfs文件系统\033[0m"
mkfs.xfs /dev/$vgname/$lvmname
if [ $? == 0 ]
then 
	mkdir -p $partition
	echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m更新/etc/fstab\033[0m"
	echo "/dev/$vgname/$lvmname  $partition  xfs     defaults        0 0" >> /etc/fstab
	mount -a
	echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mlvm创建成功\033[0m"
	echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mlvm文件系统磁盘空间使用情况：\033[0m"
	df -h
else
	echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31mlvm创建失败！\033[0m"
fi
