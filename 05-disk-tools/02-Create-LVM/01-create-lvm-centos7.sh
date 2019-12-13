#!/bin/bash
# only use in centos7
partition=/data                # 定义最终挂载的名称
vgname=vgdata                      # 定义逻辑卷组的名称
lvmname=lvmdata                     # 定义逻辑卷的名称
code='vdb'   # 根据分区的实际情况修改
 
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
echo $disk
done
 
pvcreate $disk
pvdisplay
vgcreate $vgname $disk
vgdisplay
lvcreate -l 100%VG -n $lvmname $vgname
lvdisplay
echo "start mkfs....."
sleep 2
mkfs.xfs /dev/$vgname/$lvmname
if [ $? == 0 ]
then 
	mkdir -p $partition
	echo "/dev/$vgname/$lvmname  $partition  xfs     defaults        0 0" >> /etc/fstab
	mount -a
	df -h
	echo "lvm create and mount successful!"

else

	echo "lvm create fail!"
fi

