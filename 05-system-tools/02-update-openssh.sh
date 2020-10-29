#!/bin/bash
# centos7.6下进行的测试
# 本脚本中为了加速下载，使用的是腾讯云镜像站下载，如果想访问官网下载：
# openssl官网下载：wget https://ftp.openssl.org/source/openssl-${openssl_version}.tar.gz
# openssh官网下载：wget https://openbsd.hk/pub/OpenBSD/OpenSSH/portable/openssh-${openssh_version}.tar.gz

# 如果没有检测到tar.gz包，则下载到这个目录
openssh_source_dir=$(pwd)/openssh-update
openssl_version=1.1.1h
openssh_version=8.4p1

echo -e "\033[32m[#] 现在的版本：\033[0m"
openssl version
ssh -V
echo # 换行，美观
sleep 2

# 多核编译
function multi_core_compile(){
    assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
    cpucores=$(cat /proc/cpuinfo | grep -c processor)
    compilecore=$(($cpucores - $assumeused - 1))
    if [ $compilecore -ge 1 ];then
        make -j $compilecore && make -j $compilecore install
        if [ $? -ne 0 ];then
            echo -e "\n\033[31m[*] 编译安装出错，请检查脚本\033[0m\n"
            exit 1
        fi
    else
        make && make install
        if [ $? -ne 0 ];then
            echo -e "\n\033[31m[*] 编译安装出错，请检查脚本\033[0m\n"
            exit 1
        fi 
    fi
}

# 解压
function untar_tgz(){
    echo -e "\033[32m[+] 解压 $1 中\033[0m"
    tar xf $1
    if [ $? -ne 0 ];then
        echo -e "\033[31m[*] 解压出错，请检查!\033[0m"
        exit 2
    fi
}

# 首先判断当前目录是否有压缩包：
#   I. 如果有压缩包，那么就在当前目录解压；
#   II.如果没有压缩包，那么就检查有没有 ${openssh_source_dir} 表示的目录;
#       1) 如果有目录，那么检查有没有压缩包
#           ① 有压缩包就解压
#           ② 没有压缩包则下载压缩包
#       2) 如果没有,那么就创建这个目录，然后 cd 到目录中，然后下载压缩包，然
#       后解压
# 解压的步骤都在后面，故此处只做下载

# 语法： download_tar_gz 文件名 保存的目录 下载链接
# 使用示例： download_tar_gz openssl-1.1.1h.tar.gz /data/openssh-update https://mirrors.cloud.tencent.com/openssl/source/openssl-1.1.1h.tar.gz
function download_tar_gz(){
    back_dir=$(pwd)
    file_in_the_dir=''  # 这个目录是后面编译目录的父目录

    ls $1 &> /dev/null
    if [ $? -ne 0 ];then
        # 进入此处表示脚本所在目录没有压缩包
        ls -d $2 &> /dev/null
        if [ $? -ne 0 ];then
            # 进入此处表示没有${openssh_source_dir}目录
            mkdir -p $2 && cd $2
            echo -e "\033[32m[+] 下载源码包 $1 至 $(pwd)/\033[0m"
            wget $3
            file_in_the_dir=$(pwd)
            # 返回脚本所在目录，这样这个函数才可以多次使用
            cd ${back_dir}
        else
            # 进入此处表示有${openssh_source_dir}目录
            cd $2
            ls $1 &> /dev/null
            if [ $? -ne 0 ];then
            # 进入此处表示${openssh_source_dir}目录内没有压缩包
                echo -e "\033[32m[+] 下载源码包 $1 至 $(pwd)/\033[0m"
                wget $3
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            else
                # 进入此处，表示${openssh_source_dir}目录内有压缩包
                echo -e "\033[32m[!] 发现压缩包$(pwd)/$1\033[0m"
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            fi
        fi
    else
        # 进入此处表示脚本所在目录有压缩包
        echo -e "\033[32m[!] 发现压缩包$(pwd)/$1\033[0m"
        file_in_the_dir=$(pwd)
    fi
}

# 升级openssl
echo -e "\033[36m[+] 升级 openssl\033[0m"

yum install -y gcc
echo -e "\033[32m[+] 备份 /usr/bin/openssl 为 /usr/bin/openssl_old\033[0m"
mv -f /usr/bin/openssl /usr/bin/openssl_old

download_tar_gz openssl-${openssl_version}.tar.gz ${openssh_source_dir} https://mirrors.cloud.tencent.com/openssl/source/openssl-${openssl_version}.tar.gz
cd ${file_in_the_dir}
untar_tgz openssl-${openssl_version}.tar.gz

cd openssl-${openssl_version}
./config shared
multi_core_compile 

echo -e "\033[32m[+] 配置软链接\033[0m"
ln -s /usr/local/bin/openssl /usr/bin/openssl
[ -f /usr/lib64/libssl.so.1.1 ] || ln -s /usr/local/lib64/libssl.so.1.1 /usr/lib64/
[ -f /usr/lib64/libcrypto.so.1.1 ] || ln -s /usr/local/lib64/libcrypto.so.1.1 /usr/lib64/

# 退出openssl源码目录
cd ..

echo -e "\033[32m[+] 备份 /etc/ssh目录 为 /etc/ssh_old目录\033[0m"
[ -d /etc/ssh_old ] && rm -rf /etc/ssh_old
mkdir /etc/ssh_old
mv /etc/ssh/* /etc/ssh_old/


# 升级openssh
echo -e "\033[36m[+] 升级 openssh\033[0m"
yum install zlib-devel openssl-devel pam-devel -y
download_tar_gz openssh-${openssh_version}.tar.gz ${openssh_source_dir} https://mirrors.cloud.tencent.com/OpenBSD/OpenSSH/portable/openssh-${openssh_version}.tar.gz
cd ${file_in_the_dir}
untar_tgz openssh-${openssh_version}.tar.gz

cd openssh-${openssh_version}
./configure --prefix=/usr/ --sysconfdir=/etc/ssh --with-ssl-dir=/usr/local/lib64/ --with-zlib --with-pam --with-md5-password --with-ssl-engine --with-selinux
multi_core_compile

echo -e "\033[32m[+] 优化sshd_config\033[0m"
sed -i '/^#PermitRootLogin/s/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config 
sed -i '/^#UseDNS/s/#UseDNS.*/UseDNS no/' /etc/ssh/sshd_config

echo -e "\033[32m[+] 优化sshd.service\033[0m"
sed -i 's/^Type/#&/' /usr/lib/systemd/system/sshd.service

echo -e "\033[32m[#] 升级后的版本：\033[0m"
openssl version
ssh -V

echo -e "\033[32m[>] 重启sshd服务\033[0m"
systemctl daemon-reload
systemctl restart sshd