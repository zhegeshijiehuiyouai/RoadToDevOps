#!/bin/bash
# centos7.6下进行的测试

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
        make -j $compilecore && make install
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

function mkdir_and_cd () {
    [ -d ${openssh_source_dir} ] || mkdir ${openssh_source_dir}
    cd ${openssh_source_dir}
}


# 判断压缩包是否存在，如果不存在就下载
ls openssl-${openssl_version}.tar.gz &> /dev/null
if [ $? -ne 0 ];then
    mkdir_and_cd
    echo -e "\033[32m[+] 下载openssl源码包\033[0m"
    #wget https://ftp.openssl.org/source/openssl-${openssl_version}.tar.gz
    wget https://mirrors.cloud.tencent.com/openssl/source/openssl-${openssl_version}.tar.gz
fi
ls openssh-${openssh_version}.tar.gz &> /dev/null
if [ $? -ne 0 ];then
    echo -e "\033[32m[+] 下载openssh源码包\033[0m"
    #wget https://openbsd.hk/pub/OpenBSD/OpenSSH/portable/openssh-${openssh_version}.tar.gz
    wget https://mirrors.cloud.tencent.com/OpenBSD/OpenSSH/portable/openssh-${openssh_version}.tar.gz
fi


yum install -y gcc
echo -e "\033[32m[+] 备份 /usr/bin/openssl 为 /usr/bin/openssl_old\033[0m"
mv -f /usr/bin/openssl /usr/bin/openssl_old

echo -e "\033[36m[+] 升级 openssl\033[0m"
echo -e "\033[32m[+] 解压 openssl-${openssl_version}.tar.gz\033[0m"
tar xf openssl-${openssl_version}.tar.gz
cd openssl-${openssl_version}
./config shared
multi_core_compile 
make install

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


yum install zlib-devel openssl-devel pam-devel -y
echo -e "\033[36m[+] 升级 openssh\033[0m"
echo -e "\033[32m[+] 解压 openssh-${openssh_version}.tar.gz\033[0m"
tar xf openssh-${openssh_version}.tar.gz
cd openssh-${openssh_version}
./configure --prefix=/usr/ --sysconfdir=/etc/ssh --with-ssl-dir=/usr/local/lib64/ --with-zlib --with-pam --with-md5-password --with-ssl-engine --with-selinux
multi_core_compile
make install

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