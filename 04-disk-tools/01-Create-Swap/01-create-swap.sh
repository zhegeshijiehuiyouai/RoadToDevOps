#!/bin/bash

# 单位只能为G
SWAP_SIZE=2G
SWAP_FILE_NAME=swap
SWAP_DIR=$(pwd)/${SWAP_FILE_NAME}
# 修复在根目录下创建swap文件时，有两个/的问题
if [[ $(pwd) == "/" ]];then
    SWAP_DIR=/${SWAP_FILE_NAME}
fi

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

if [[ ! ${SWAP_SIZE} =~ G$ ]];then
    echo_error swap单位设置错误
    exit 1
fi

echo_info 请确认信息，如需调整请修改脚本
echo "swap大小：${SWAP_SIZE}"
echo "swap文件路径：${SWAP_DIR}"
echo_info "确认(y|N)："
read USER_INPUT
case ${USER_INPUT} in
    y|Y|yes)
        echo
        ;;
    *)
        exit 2
        ;;
esac

echo_info 设置swap亲和度为30
sysctl -w vm.swappiness=30
sed -i 's/vm.swappiness = 0/vm.swappiness = 30/g' /etc/sysctl.conf

echo_info "swap文件${SWAP_DIR}(${SWAP_SIZE})创建中，请耐心等待..."

SWAP_SIZE=$(echo ${SWAP_SIZE} | cut -d"G" -f 1)
DD_BS=$((512*${SWAP_SIZE}))
dd if=/dev/zero of=${SWAP_DIR} bs=${DD_BS} count=2097152

mkswap ${SWAP_DIR}
chmod 0600 ${SWAP_DIR}

echo_info 挂载swap
swapon ${SWAP_DIR}
echo -e "${SWAP_DIR}\t\tswap\t\t\tswap\tdefaults\t0 0" >> /etc/fstab

echo_info swap已创建成功
free -h