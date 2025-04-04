#!/bin/bash

##### 配置 #####
script_dir=$(dirname $(realpath $0))
src_dir=${script_dir}/00src00



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

# 检测操作系统
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
    # 阻止配置更新弹窗
    export UCF_FORCE_CONFFOLD=1
    # 阻止应用重启弹窗
    export NEEDRESTART_SUSPEND=1
elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
    if echo "$os_version" | grep -q '^7'; then
        true
    else
        echo "仅支持centos7"
        exit 99
    fi
else
	echo_error 不支持的操作系统
	exit 99
fi

function install_local_rpm() {
    exist_kernel_rpm=$1
    echo_info "发现kernel安装包：${exist_kernel_rpm}，是否安装[y/n]"
    read is_install
    case $is_install in
    y|Y)
        echo_info 安装${exist_kernel_rpm}
        yum install -y ${exist_kernel_rpm}
        ;;
    n|N)
        echo_info 用户取消
        exit 0
        ;;
    *)
        install_local_rpm
        ;;
    esac
}

function install_newest_ml_kernel() {
    echo_info 添加镜像源
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    wait
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-5.el7.elrepo.noarch.rpm
    wait
    echo_info 安装主线最新版本的内核
    yum --enablerepo=elrepo-kernel install kernel-ml -y
    wait
}

function install_internet_rpm() {
    read choice
    case $choice in
    1)
        install_newest_ml_kernel
        ;;
    2)
        echo_info "提供两个kernel下载地址："
        echo "coreix源，包全，速度中等：http://mirrors.coreix.net/elrepo-archive-archive/kernel/el7/x86_64/RPMS/"
        echo "阿里源，包较少，速度快：  http://mirrors.aliyun.com/elrepo/kernel/el7/x86_64/RPMS/ (疑似已失效)"
        exit 0
        ;;
    *)
        install_internet_rpm
        ;;
    esac
}


############################### 开始 ########################################
echo_info "当前内核版本：$(uname -r)"
# 判断本地是否有安装包
exist_kernel_rpm=$(ls | egrep -o "^kernel-(lt|ml)-[0-9].*rpm$")
if [ $? -eq 0 ];then
    install_local_rpm ${exist_kernel_rpm}
elif [ -d ${src_dir} ];then
    exist_kernel_rpm=$(ls ${src_dir} | egrep -o "^kernel-(lt|ml)-[0-9].*rpm$")
    if [ $? -eq 0 ];then
        install_local_rpm ${src_dir}/${exist_kernel_rpm}
    else
        # 通过互联网安装
        echo_info "请输入数字选择升级到的kernel版本："
        echo -e "\033[36m[1]\033[32m 主线最新版本\033[0m"
        echo -e "\033[36m[2]\033[32m 自己下载rpm包，然后上传到 $(pwd) ，再重新执行脚本\033[0m"
        install_internet_rpm
    fi
# 通过互联网安装
else
    echo_info "请输入数字选择升级到的kernel版本："
    echo -e "\033[36m[1]\033[32m 主线最新版本\033[0m"
    echo -e "\033[36m[2]\033[32m 自己下载rpm包，然后上传到 $(pwd) ，再重新执行脚本\033[0m"
    install_internet_rpm
fi



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

sysctl --system

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
