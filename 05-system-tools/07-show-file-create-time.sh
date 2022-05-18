#!/bin/sh
# 脚本来自：https://cloud.tencent.com/developer/article/1726834


[ $# -ne 1 ] && echo "用法： $0 {FILENAME}" && exit 1

INODE=`ls -i $1 |awk '{print $1}'`
FILENAME=$1

# 如果传入参数带/，则获取这个传入参数的目录路径并进入目录
`echo $FILENAME | grep / 1> /dev/null` && { FPWD=${FILENAME%/*};FPWD=${FPWD:=/};cd ${FPWD};FPWD=`pwd`; } || FPWD=`pwd`

array=(`echo ${FPWD} | sed 's@/@ @g'`)
array_length=${#array[@]}

for ((i=${array_length};i>=0;i--)); do
 unset array[$i]
 SUBPWD=`echo " "${array[@]} | sed 's@ @/@g'`
 DISK=`df -h |grep ${SUBPWD}$ |awk '{print $1}'`
 [[ -n $DISK ]] && break
done

# 文件系统非ext4则退出
[[ "`df -T | grep ${DISK} |awk '{print $2}'`" != "ext4" ]] && { echo ${DISK} 不是ext4格式，脚本只支持ext4格式的文件系统;exit 2; }

debugfs -R "stat <${INODE}>" ${DISK} | grep crtime