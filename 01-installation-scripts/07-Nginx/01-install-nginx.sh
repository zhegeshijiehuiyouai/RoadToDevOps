#!/bin/bash
# 编译安装Nginx

# nginx的版本
version=1.19.2
# 部署目录
installdir=/data/nginx

# 判断压缩包是否存在，如果不存在就下载
ls nginx-${version}.tar.gz &> /dev/null
[ $? -eq 0 ] || wget http://nginx.org/download/nginx-${version}.tar.gz

# 解压
echo "解压中，请稍候..."
tar xf nginx-${version}.tar.gz
if [ $? -ne 0 ];then
    echo "\n\033[31m解压出错，请检查\033[0m\n"
    exit 2
fi

yum install -y gcc zlib zlib-devel openssl openssl-devel pcre pcre-devel

cd nginx-${version}
./configure --prefix=${installdir} --with-pcre --with-http_ssl_module --with-http_v2_module --with-stream

# 配置多核编译
assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
cpucores=$(cat /proc/cpuinfo | grep -c processor)
compilecore=$(($cpucores - $assumeused - 1))
if [ $compilecore -ge 1 ];then
    make -j $compilecore && make install
    if [ $? -ne 0 ];then
        echo -e "\n\033[31m编译安装出错，请检查脚本\033[0m\n"
        exit 1
    fi
else
    make && make install
    if [ $? -ne 0 ];then
        echo -e "\n\033[31m编译安装出错，请检查脚本\033[0m\n"
        exit 1
    fi 
fi

echo -e "\n\n\033[33mNginx已安装在\033[0m${installdir}\033[33m，详细信息如下：\033[0m\n"
${installdir}/sbin/nginx -V
echo -e "\n"
