#!/bin/bash

shc_version=4.0.3
src_dir=$(pwd)/00src00


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
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)
elif [[ -e /etc/almalinux-release ]]; then
    os="alma"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/almalinux-release)
else
	true # 这个脚本不用区分发行版
fi

# 解压
function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
        exit 2
    fi
}

# 首先判断当前目录是否有压缩包：
#   I. 如果有压缩包，那么就在当前目录解压；
#   II.如果没有压缩包，那么就检查有没有 ${src_dir} 表示的目录;
#       1) 如果有目录，那么检查有没有压缩包
#           ① 有压缩包就解压
#           ② 没有压缩包则下载压缩包
#       2) 如果没有,那么就创建这个目录，然后 cd 到目录中，然后下载压缩包，然
#       后解压
# 解压的步骤都在后面，故此处只做下载

# 语法： download_tar_gz 保存的目录 下载链接
# 使用示例： download_tar_gz /data/openssh-update https://mirrors.cloud.tencent.com/openssl/source/openssl-1.1.1h.tar.gz
function check_downloadfile() {
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IksS $1 | head -1 | awk '{print $2}')
    if [ "${http_code}" == "404" ];then
        echo_error $1
        echo_error 服务端文件不存在，退出
        exit 98
    fi
}
function install_wget() {
    if [ ! -f /usr/bin/wget ];then
        echo_info 安装wget工具
        if [[ $os == "centos" ]];then
            yum install -y wget
        elif [[ $os == "ubuntu" ]];then
            apt install -y wget
        elif [[ $os == 'rocky' || $os == 'alma' ]];then
            dnf install -y wget
        fi
    fi
}
function download_tar_gz(){
    download_file_name=$(echo $2 |  awk -F"/" '{print $NF}')
    back_dir=$(pwd)
    file_in_the_dir=''  # 这个目录是后面编译目录的父目录

    # 脚本所在目录有压缩包
    if [ -f "${download_file_name}" ];then
        echo_info 发现压缩包$(pwd)/$download_file_name
        file_in_the_dir=$(pwd)
        return
    fi

    # 确保目标目录存在
    [ -d "$1" ] || mkdir -p "$1"
    cd "$1"

    # 目标目录中有压缩包
    if [ -f "${download_file_name}" ];then
        echo_info 发现压缩包$(pwd)/$download_file_name
        file_in_the_dir=$(pwd)
        cd "${back_dir}"
        return
    fi

    # 需要下载
    echo_info 下载 $download_file_name 至 $(pwd)/
    install_wget
    check_downloadfile $2
    wget --no-check-certificate $2
    if [ $? -ne 0 ];then
        echo_error 下载 $2 失败！
        exit 1
    fi
    file_in_the_dir=$(pwd)
    cd "${back_dir}"
}

function pre_make() {
    if [[ $os == "centos" ]];then
        yum install -y gcc
    elif [[ $os == "ubuntu" ]];then
        apt install -y build-essential
    elif [[ $os == "rocky" || $os == "alma" ]];then
        dnf install -y gcc
    fi
}

# 多核编译
function multi_core_compile(){
    # 检查make存不存在
    make --version &> /dev/null
    if [ $? -ne 0 ];then
        if [[ $os == "centos" ]];then
            yum install -y make
        elif [[ $os == "ubuntu" ]];then
            apt install -y make
        elif [[ $os == "rocky" || $os == "alma" ]];then
            dnf install -y make
        fi
    fi
    assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
    cpucores=$(cat /proc/cpuinfo | grep -c processor)
    compilecore=$(($cpucores - $assumeused - 1))
    if [ $compilecore -ge 1 ];then
        make -j $compilecore && make -j $compilecore install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi
    else
        make && make install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi 
    fi
}

download_tar_gz ${src_dir} https://cors.isteed.cc/https://github.com/neurobin/shc/archive/refs/tags/${shc_version}.tar.gz
cd ${file_in_the_dir}
[ -d shc-${shc_version} ] && rm -rf shc-${shc_version}
untar_tgz ${shc_version}.tar.gz
cd shc-${shc_version}
pre_make
./configure
multi_core_compile
if [ $? -ne 0 ];then
    echo_error 编译失败！
    exit 1
fi
echo_info 清理文件
cd ..
rm -rf shc-${shc_version}

echo_info shc已部署完毕，使用示例：
echo "                  shc -f yourfile.sh"
echo