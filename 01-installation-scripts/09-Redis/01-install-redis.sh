#!/bin/bash

# 脚本功能：自动部署redis
# 测试系统：CentOS7.6
# 说明：可编译各版本的reids（包括6.x），多核编译哦~~~
# 切换版本：如果是【官网可下载】的版本，那么直接修改本脚本中 FILE=redis-6.0.8 为 FILE=对应版本，即可
#         如果是【非官网下载】的版本，那么先下载好tar.gz包，然后在修改脚本中的FILE即可
# 卸载：未添加环境变量，直接删除redis目录即可

# 监听地址
listen_ip=0.0.0.0
# 端口
PORT=6379
# redis的密码
redis_pass=OrcMu4tDie
# 解压后的名字
FILE=redis-6.0.8
# redis源码包名字
Archive=${FILE}.tar.gz

# 如果同端口已被占用，则直接退出
netstat -tnlp | grep ${PORT}
if [ $? -eq 0 ];then
    echo -e "\033[32m\n[*] ${PORT} 端口已被占用！\n退出...\033[0m"
    exit 21
fi

# 判断压缩包是否存在，如果不存在就下载
ls ${Archive} &> /dev/null
if [ $? -ne 0 ];then
    echo -e "\033[32m[+] 下载Redis源码包 ${Archive}\033[0m"
    wget http://download.redis.io/releases/${Archive}
fi

# 解压
echo -e "\033[32m[+] 解压 ${Archive} 中，请稍候...\033[0m"
tar xf ${Archive} >/dev/null 2>&1
if [ $? -eq 0 ];then
    echo -e "\033[32m[+] 解压完毕\033[0m"
else
    echo -e "\033[31m[*] 解压出错，请检查!\033[0m"
    exit 2
fi

# 更改文件名
redis_dir_name=redis
mv ${FILE} ${redis_dir_name}

cd ${redis_dir_name}
redis_home=$(pwd)

echo -e "\033[32m[+] 检查编译环境\033[0m"
yum install -y gcc
yum install -y centos-release-scl-rh 
yum install -y devtoolset-9-gcc devtoolset-9-gcc-c++ devtoolset-9-binutils
# 升级gcc，6.x版本需要
source /opt/rh/devtoolset-9/enable

echo -e "\033[32m[>] 编译redis\033[0m"
# 清理先前编译出错的内容
make distclean
# 配置多核编译
assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
cpucores=$(cat /proc/cpuinfo | grep -c processor)
compilecore=$(($cpucores - $assumeused - 1))
if [ $compilecore -ge 1 ];then
    make -j $compilecore
    if [ $? -ne 0 ];then
        echo -e "\n\033[31m[*] 编译出错，请检查脚本\033[0m\n"
        exit 1
    fi
else
    make
    if [ $? -ne 0 ];then
        echo -e "\n\033[31m[*] 编译出错，请检查脚本\033[0m\n"
        exit 1
    fi 
fi

echo -e "\033[36m\n[+] 优化redis.conf文件\033[0m"
sed -i 's/^daemonize no/daemonize yes/' redis.conf

# 解决单引号里无法使用变量的问题
cat > /tmp/_redis_file1 << EOF
sed -i 's@^port.*@port ${PORT}@' redis.conf
sed -i 's@^dbfilename.*@dbfilename dump-${PORT}.rdb@' redis.conf
sed -i 's@^# requirepass.*@requirepass ${redis_pass}@' redis.conf
sed -i 's@^bind.*@bind ${listen_ip}@' redis.conf

[ -d logs ] || mkdir logs
sed -i 's@^logfile.*@logfile "${redis_home}/logs/redis-${PORT}.log"@' redis.conf
[ -d data ] || mkdir data
sed -i 's@^dir.*@dir "${redis_home}/data/"@' redis.conf
EOF
/bin/bash /tmp/_redis_file1
rm -f /tmp/_redis_file1

echo -e "\033[32m\n[>] redis已编译成功，详细信息如下：\033[0m"
echo -e "\033[32m    部署版本： \033[33m${FILE}\033[0m"
echo -e "\033[32m    监听IP：   \033[33m${listen_ip}\033[0m"
echo -e "\033[32m    监听端口： \033[33m${PORT}\033[0m"
echo -e "\033[32m    redis密码：\033[33m${redis_pass}\033[0m"

echo -e "\033[32m\n[>] 启动redis\033[0m"
${redis_home}/src/redis-server ${redis_home}/redis.conf
sleep 2
netstat -tnlp | grep ${PORT}
if [ $? -eq 0 ];then
    echo -e "\033[32m\n[>] redis已启动！\n启动命令：\033[36m${redis_home}/src/redis-server ${redis_home}/redis.conf\n\033[0m"
else
    echo -e "\033[31m[*] 启动失败，请检查配置！\n\033[0m"
    exit 20
fi

echo -e "\033[32m[#] iredis介绍：\033[0m"
echo -e "\033[32m    iredis是一个具有代码补全和语法高亮的redis命令行客户端，github项目地址：\033[0m"
echo -e "\033[32m    https://github.com/laixintao/iredis\033[0m"
function iredisyn() {
read -p "[>] 是否添加iredis (y/n)：" choice
case ${choice} in
    y|Y)
        yum install -y python3-pip
        pip3 install iredis -i https://pypi.tuna.tsinghua.edu.cn/simple
        echo
        ;;
    n|N)
        echo
        exit 14
        ;;
    *)
        iredisyn
        ;;
esac
}
iredisyn
