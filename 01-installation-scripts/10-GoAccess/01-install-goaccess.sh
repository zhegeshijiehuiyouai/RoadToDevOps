#!/bin/bash 

# 定义变量
version=1.4

# GeoIP2需要从 MaxMind 下载 城市/国家 数据库，并通过 --geoip-database 设定。
# 如果使用 GeoIP，则不用下载数据库。
# MaxMind官网：https://dev.maxmind.com/geoip/geoip2/geolite2/
# 必须注册登录下载，注册登录后，进入自己的账号界面，有下载链接
#
# 使用 GeoIP2 的话，需要安装依赖库
# wget https://github.com/maxmind/libmaxminddb/releases/download/1.4.3/libmaxminddb-1.4.3.tar.gz
# tar xf libmaxminddb-1.4.3.tar.gz
# cd libmaxminddb-1.4.3
# ./configure
# make
# make install
# sh -c "echo /usr/local/lib  >> /etc/ld.so.conf.d/local.conf"
# ldconfig

# 判断压缩包是否存在，如果不存在就下载
ls goaccess-${version}.tar.gz &> /dev/null
if [ $? -ne 0 ];then
    echo -e "\033[32m[+] 下载 goaccess 源码包 goaccess-${version}.tar.gz\033[0m"
    wget https://tar.goaccess.io/goaccess-${version}.tar.gz
fi

echo -e "\033[32m[+] 解压 goaccess-${version}.tar.gz 中，请稍候...\033[0m"
tar xf goaccess-${version}.tar.gz
if [ $? -eq 0 ];then
    echo -e "\033[32m[+] 解压完毕\033[0m"
else
    echo -e "\033[31m[*] 解压出错，请检查!\033[0m"
    exit 2
fi

echo -e "\033[32m[+] 检查编译环境\033[0m"
yum install -y openssl-devel GeoIP-devel ncurses-devel epel-release gcc

echo -e "\033[32m[>] 编译 goaccess\033[0m"
cd goaccess-${version}
#./configure --enable-utf8 --enable-geoip=mmdb --with-openssl --with-getline --enable-tcb=memhash
./configure --enable-utf8 --enable-geoip=legacy --with-openssl --with-getline --enable-tcb=memhash

# 配置多核编译
assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
cpucores=$(cat /proc/cpuinfo | grep -c processor)
compilecore=$(($cpucores - $assumeused - 1))
if [ $compilecore -ge 1 ];then
    make -j $compilecore && make -j $compilecore install
    if [ $? -ne 0 ];then
        echo -e "\n\033[31m[*] 编译出错，请检查脚本\033[0m\n"
        exit 1
    fi
else
    make && make install
    if [ $? -ne 0 ];then
        echo -e "\n\033[31m[*] 编译出错，请检查脚本\033[0m\n"
        exit 1
    fi
fi

echo -e "\033[36m\n[+] 设置配置文件 为 nginx 日志分析模式\033[0m"
sed -i 's@^#time-format %H:%M:%S@time-format %H:%M:%S@' /usr/local/etc/goaccess/goaccess.conf
sed -i 's@^#date-format %d/%b/%Y@date-format %d/%b/%Y@' /usr/local/etc/goaccess/goaccess.conf
sed -i 's@#log-format COMBINED@log-format COMBINED@' /usr/local/etc/goaccess/goaccess.conf

echo -e "\033[32m\n[>] goaccess 已编译安装成功，详细信息如下：\033[0m"
echo -e -n "\033[33m"
echo "配置文件路径：/usr/local/etc/goaccess/goaccess.conf"
goaccess -V
echo 
echo "设置输出html为中文："
echo -e "\033[36mexport LANG=zh_CN.UTF-8\033[33m"
echo "用法举例："
echo -e "\033[36mgoaccess -a -g -f yourlogfile -o output.html\033[0m\n"