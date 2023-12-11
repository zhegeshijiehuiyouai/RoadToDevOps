#!/bin/bash
# centos7.6下进行的测试
# 本脚本中为了加速下载，使用的是腾讯云镜像站下载，如果想访问官网下载：
# openssl官网下载：wget https://ftp.openssl.org/source/openssl-${openssl_version}.tar.gz
# openssl官网只有最新版，需要老版本的话，从这个下载：https://www.openssl.org/source/old/
# openssh官网下载：wget https://openbsd.hk/pub/OpenBSD/OpenSSH/portable/openssh-${openssh_version}.tar.gz

# 如果没有检测到tar.gz包，则下载到这个目录
openssh_source_dir=$(pwd)/00src00
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
function download_tar_gz(){
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IsS $2 | head -1 | awk '{print $2}')
    if [ $http_code -eq 404 ];then
        echo_error $2
        echo_error 服务端文件不存在，退出
        exit 98
    fi
    
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
                yum install -y wget
            fi
            wget $2
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
                    yum install -y wget
                fi
                wget $2
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

yum install -y gcc
echo_info 备份 /usr/bin/openssl 为 /usr/bin/openssl_old
mv -f /usr/bin/openssl /usr/bin/openssl_old

download_tar_gz ${openssh_source_dir} https://mirrors.cloud.tencent.com/openssl/source/openssl-${openssl_version}.tar.gz
cd ${file_in_the_dir}
untar_tgz openssl-${openssl_version}.tar.gz

cd openssl-${openssl_version}
./config shared
multi_core_compile 

echo_info 配置软链接
ln -s /usr/local/bin/openssl /usr/bin/openssl
[ -f /usr/lib64/libssl.so.1.1 ] || ln -s /usr/local/lib64/libssl.so.1.1 /usr/lib64/
[ -f /usr/lib64/libcrypto.so.1.1 ] || ln -s /usr/local/lib64/libcrypto.so.1.1 /usr/lib64/

# 退出openssl源码目录
cd ..

echo_info 备份 /etc/ssh目录 为 /etc/ssh_old目录
[ -d /etc/ssh_old ] && rm -rf /etc/ssh_old
mkdir /etc/ssh_old
mv /etc/ssh/* /etc/ssh_old/


# 升级openssh
echo_info 准备升级 openssh

yum install zlib-devel openssl-devel pam-devel -y
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
openssl version
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