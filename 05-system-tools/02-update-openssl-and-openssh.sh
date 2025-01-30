#!/bin/bash
# centos7.9下进行的测试
# 本脚本中为了加速下载，使用的是腾讯云镜像站下载，如果想访问官网下载：
# openssl官网下载：wget https://ftp.openssl.org/source/openssl-${openssl_version}.tar.gz
# openssl官网只有最新版，需要老版本的话，从这个下载：https://www.openssl.org/source/old/
# openssh官网下载：wget https://openbsd.hk/pub/OpenBSD/OpenSSH/portable/openssh-${openssh_version}.tar.gz

# 如果没有检测到tar.gz包，则下载到这个目录
openssh_source_dir=$(pwd)/00src00
openssl_prefix_dir=/usr/local/openssl
openssl_version=1.1.1w
openssh_version=8.4p1

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

function user_confirm() {
    read -e user_confirm_input
    case $user_confirm_input in
    y|Y)
        true
        ;;
    n|N)
        echo_info 用户取消
        exit 0
        ;;
    *)
        echo 请输入y或n
        user_confirm
        ;;
    esac
}

# 检测操作系统
if [[ ! -e /etc/centos-release ]]; then
    echo_warning "本脚本仅针对 CentOS 7，是否继续[y/n]"
    user_confirm
fi

function confirm_installation(){
    read -p "请输入数字选择要升级的内容（如需退出请输入q）：" -e confirm_installation_input
    case $confirm_installation_input in
        1)
            only_openssl_tag=1
            ;;
        2)
            only_openssl_tag=2
            ;;
        q|Q)
            exit 0
            ;;
        *)
            confirm_installation
            ;;
    esac
}
echo -e "\033[31m请选择升级内容：\033[0m"
echo -e "\033[36m[1]\033[32m 只升级openssl\033[0m"
echo -e "\033[36m[2]\033[32m 同时升级openssl和openssh\033[0m"
confirm_installation

echo_info 现在的版本：
openssl version
ssh -V

# 多核编译
function multi_core_compile(){
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
    if [ $http_code -eq 404 ];then
        echo_error $1
        echo_error 服务端文件不存在，退出
        exit 98
    fi
}
function download_tar_gz(){
    download_file_name=$(echo $2 |  awk -F"/" '{print $NF}')
    back_dir=$(pwd)
    file_in_the_dir=''  # 这个目录是后面编译目录的父目录

    ls $download_file_name &> /dev/null
    if [ $? -ne 0 ];then
        # 进入此处表示脚本所在目录没有压缩包
        ls -d $1 &> /dev/null
        if [ $? -ne 0 ];then
            # 进入此处表示没有${src_dir}目录
            mkdir -p $1 && cd $1
            echo_info 下载 $download_file_name 至 $(pwd)/
            # 检测是否有wget工具
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
            check_downloadfile $2
            wget --no-check-certificate $2
            if [ $? -ne 0 ];then
                echo_error 下载 $2 失败！
                exit 1
            fi
            file_in_the_dir=$(pwd)
            # 返回脚本所在目录，这样这个函数才可以多次使用
            cd ${back_dir}
        else
            # 进入此处表示有${src_dir}目录
            cd $1
            ls $download_file_name &> /dev/null
            if [ $? -ne 0 ];then
            # 进入此处表示${src_dir}目录内没有压缩包
                echo_info 下载 $download_file_name 至 $(pwd)/
                # 检测是否有wget工具
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
                check_downloadfile $2
                wget --no-check-certificate $2
                if [ $? -ne 0 ];then
                    echo_error 下载 $2 失败！
                    exit 1
                fi
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            else
                # 进入此处，表示${src_dir}目录内有压缩包
                echo_info 发现压缩包$(pwd)/$download_file_name
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            fi
        fi
    else
        # 进入此处表示脚本所在目录有压缩包
        echo_info 发现压缩包$(pwd)/$download_file_name
        file_in_the_dir=$(pwd)
    fi
}

# 升级openssl
echo_info 准备升级 openssl
yum install -y gcc zlib-devel
echo_info 备份 /usr/bin/openssl 为 /usr/bin/openssl_old
mv -f /usr/bin/openssl /usr/bin/openssl_old

download_tar_gz ${openssh_source_dir} https://mirrors.cloud.tencent.com/openssl/source/openssl-${openssl_version}.tar.gz
cd ${file_in_the_dir}
untar_tgz openssl-${openssl_version}.tar.gz

cd openssl-${openssl_version}
./config --prefix=${openssl_prefix_dir} --openssldir=${openssl_prefix_dir} shared zlib
multi_core_compile

echo_info 更新环境变量
echo 'export PATH="'${openssl_prefix_dir}'/bin:$PATH"' > /etc/profile.d/openssl.sh
# 其他软件编译时使用到openssl的环境变量
if [ -z $LDFLAGS ];then
    echo 'export LDFLAGS="-L'${openssl_prefix_dir}'/lib"' >> /etc/profile.d/openssl.sh
fi
if [ -z $CPPFLAGS ];then
    echo 'export CPPFLAGS="-I'${openssl_prefix_dir}'/include"' >> /etc/profile.d/openssl.sh
fi
echo_info 更新动态链接器的运行时绑定
echo "${openssl_prefix_dir}/lib" > /etc/ld.so.conf.d/openssl.conf
ldconfig

# 退出openssl源码目录
cd ..

######################################################################
# 删除下面的内容的话，就是单独升级openssl
######################################################################
# 仅安装openssl
if [ $only_openssl_tag -eq 1 ];then
    exit 0
fi


[ -d /etc/ssh_old ] && rm -rf /etc/ssh_old
mkdir /etc/ssh_old
mv /etc/ssh/* /etc/ssh_old/
echo_info 已将原 /etc/ssh 目录 备份到 /etc/ssh_old 目录

# 升级openssh
echo_info 准备升级 openssh
yum install openssl-devel pam-devel zlib-devel -y
download_tar_gz ${openssh_source_dir} https://mirrors.cloud.tencent.com/OpenBSD/OpenSSH/portable/openssh-${openssh_version}.tar.gz
cd ${file_in_the_dir}
untar_tgz openssh-${openssh_version}.tar.gz

cd openssh-${openssh_version}
./configure --prefix=/usr/ --sysconfdir=/etc/ssh --with-ssl-dir=/usr/local/lib64/ --with-zlib --with-pam --with-md5-password --with-ssl-engine
multi_core_compile

echo_info 优化sshd_config
sed -i '/^#PermitRootLogin/s/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 
sed -i '/^#UseDNS/s/#UseDNS.*/UseDNS no/' /etc/ssh/sshd_config

echo_info 优化sshd.service
sed -i 's/^Type/#&/' /usr/lib/systemd/system/sshd.service

echo_info 升级后的版本：
${openssl_prefix_dir}/bin/openssl version
ssh -V

echo_info 重启sshd服务
systemctl daemon-reload
systemctl restart sshd

if [ $? -eq 0 ];then
    echo_info sshd服务已成功重启
    echo_info 脚本执行完毕
else
    echo_error sshd服务重启失败，请检查
fi