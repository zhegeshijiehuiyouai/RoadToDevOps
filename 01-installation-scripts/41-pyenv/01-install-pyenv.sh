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
pyenv_root=$(pwd)/pyenv
# github镜像地址
GITHUB="https://gh.con.sh/https://github.com/"

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

if [ -d $pyenv_root ];then
    echo_error ${pyenv_root} 目录已存在，请检查是否重复安装
    exit 1
fi

# 检测操作系统
# $os_version变量并不总是存在，但为了方便，仍然保留这个变量
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	# os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)

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

if [ ! -f ~/.pip/pip.conf ]; then
    if [ ! -d ~/.pip/ ]; then
        mkdir -p ~/.pip/
    fi
    cat >> ~/.pip/pip.conf << _EOF_
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
_EOF_
fi

echo_info 安装依赖
if [[ $os == 'centos' ]];then
    pip --version &> /dev/null
    if [ $? -eq 0 ];then
        yum install -y gcc gcc-c++ zlib-devel bzip2-devel openssl-devel sqlite-devel readline-devel patch libffi-devel xz-devel
    else
        yum install -y python2-pip gcc gcc-c++ zlib-devel bzip2-devel openssl-devel sqlite-devel readline-devel patch libffi-devel xz-devel
    fi
    pip_version=$(pip --version | awk '{print $2}')
    latest_pip_version=$(echo -e "$pip_version\n20.2.4" |sort -V -r | head -1)
    # 如果当前pip版本不是最新的，那么就需要升级
    if [[ $latest_pip_version != $pip_version ]];then
        echo_info 升级pip
        wget https://mirrors.aliyun.com/macports/distfiles/py-pip/pip-20.2.4.tar.gz
        tar -zxvf pip-20.2.4.tar.gz  
        cd pip-20.2.4/
        python setup.py install
        pip install --upgrade pip 
        cd .. && rm -rf pip-20.2.4.tar.gz pip-20.2.4
    fi
elif [[ $os == 'ubuntu' ]];then
    apt update
    apt install -y python3-pip gcc g++ zlib1g-dev libbz2-dev libssl-dev libsqlite3-dev libreadline-dev libffi-dev liblzma-dev
    pip install --upgrade pip
elif [[ $os == 'rocky' ]];then
    pip --version &> /dev/null
    if [ $? -eq 0 ];then
        yum install -y gcc gcc-c++ zlib-devel bzip2-devel openssl-devel sqlite-devel readline-devel patch libffi-devel xz-devel
    else
        yum install -y python3-pip gcc gcc-c++ zlib-devel bzip2-devel openssl-devel sqlite-devel readline-devel patch libffi-devel xz-devel
    fi
    pip install --upgrade pip
fi


echo_info 克隆pyenv项目
checkout "${GITHUB}pyenv/pyenv.git"            "${pyenv_root}"                           "master"
checkout "${GITHUB}pyenv/pyenv-doctor.git"     "${pyenv_root}/plugins/pyenv-doctor"      "master"
checkout "${GITHUB}pyenv/pyenv-update.git"     "${pyenv_root}/plugins/pyenv-update"      "master"
checkout "${GITHUB}pyenv/pyenv-virtualenv.git" "${pyenv_root}/plugins/pyenv-virtualenv"  "master"
mkdir -p ${pyenv_root}/{cache,shims,versions}
chmod o+w ${pyenv_root}/{shims,versions}

echo_info 生成更新脚本
cat > ${pyenv_root}/update.sh << _EOF_
# /bin/bash

cd ${pyenv_root} && echo \$(pwd) && git pull
cd ${pyenv_root}/plugins/pyenv-doctor && echo \$(pwd) && git pull
cd ${pyenv_root}/plugins/pyenv-update && echo \$(pwd) && git pull
cd ${pyenv_root}/plugins/pyenv-virtualenv && echo \$(pwd) && git pull
_EOF_
chmod +x ${pyenv_root}/update.sh

echo_info 添加环境变量到~/.bashrc
cat >> ~/.bashrc << _EOF_
# pyenv
export PYENV_ROOT="$pyenv_root"
export PATH="\$PYENV_ROOT/bin:\$PYENV_ROOT/shims:\$PATH"
eval "\$(pyenv init -)"
eval "\$(pyenv virtualenv-init -)"
_EOF_
cd

echo
echo_info $(${pyenv_root}/bin/pyenv --version) 已安装完毕，请重新加载终端以激活pyenv命令。
echo_info pyenv升级命令：
echo "bash ${pyenv_root}/update.sh"
echo
echo_warning 本脚本仅为root用户添加了pyenv，若需为其他用户添加，请在该用户\~/.bashrc中添加以下内容
echo
cat << _EOF_
# pyenv
export PYENV_ROOT="$pyenv_root"
export PATH="\$PYENV_ROOT/bin:\$PYENV_ROOT/shims:\$PATH"
eval "\$(pyenv init -)"
eval "\$(pyenv virtualenv-init -)"
_EOF_
echo
echo_info pyenv安装python加速方法，以安装3.9.7为例
cat << _EOF_
export v=3.9.7
cd $pyenv_root/cache
wget https://registry.npmmirror.com/-/binary/python/\$v/Python-\$v.tar.xz
pyenv install \$v
_EOF_
echo