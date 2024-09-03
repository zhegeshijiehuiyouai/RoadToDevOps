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

# 包下载目录
src_dir=$(pwd)/00src00
goenv_root=$(pwd)/goenv
# github镜像地址
GITHUB="https://cors.isteed.cc/https://github.com"

echo_info 前置条件检测

# 脚本执行用户检测
if [[ $(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

if ! command -v git 1>/dev/null 2>&1; then
    echo_error 未检测到 git 命令，请先安装 git
    exit 1
fi

if [ -d $goenv_root ];then
    echo_error ${goenv_root} 目录已存在，请检查是否重复安装
    exit 1
fi

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
	echo_error 不支持的操作系统
	exit 99
fi

# 前置函数
failed_checkout() {
  echo_error "克隆失败：$1"
  exit 2
}

checkout() {
  [ -d "$2" ] || git -c advice.detachedHead=0 clone --branch "$3" --depth 1 "$1" "$2" &> /dev/null || failed_checkout "$1"
  echo_info "$1 完成"
}

echo_info 克隆goenv项目
checkout "${GITHUB}/go-nv/goenv.git"            "${goenv_root}"                           "master"
#mkdir -p ${goenv_root}/{cache,shims,versions}
#chmod o+w ${goenv_root}/{shims,versions}

echo_info 配置GOPROXY
echo "export GO111MODULE=on" > /etc/profile.d/go.sh
echo "export GOPROXY=https://goproxy.cn" >> /etc/profile.d/go.sh


echo_info 添加环境变量到~/.bashrc
cat >> ~/.bashrc << _EOF_
# goenv
export GOENV_ROOT="$goenv_root"
export PATH="\$GOENV_ROOT/bin:\$PATH"
eval "\$(goenv init -)"
_EOF_

echo
echo_info $(${goenv_root}/bin/goenv --version) 已安装完毕，请重新加载终端以激活goenv命令。
echo_warning 本脚本仅为root用户添加了goenv，若需为其他用户添加，请在该用户\~/.bashrc中添加以下内容
echo
cat << _EOF_
# goenv
export GOENV_ROOT="$goenv_root"
export PATH="\$GOENV_ROOT/bin:\$PATH"
eval "\$(goenv init -)"
_EOF_
echo