#!/bin/bash

# 脚本功能：自动部署redis
# 测试系统：CentOS7.6
# 说明：可编译各版本的reids（包括6.x），多核编译哦~~~
# 切换版本：如果是【官网可下载】的版本，那么直接修改本脚本中 FILE=redis-6.0.8 为 FILE=对应版本，即可
#         如果是【非官网下载】的版本，那么先下载好tar.gz包，然后在修改脚本中的FILE即可
# 卸载：未添加环境变量，直接删除redis目录即可

########################################
# 监听地址
listen_ip=0.0.0.0
# 端口
PORT=6379
# redis的密码
redis_pass=OrcMu4tDie
# 源码下载目录
src_dir=$(pwd)/00src00
# redis版本
redis_version=6.0.8
# 部署目录的父目录
DIR=$(pwd)
# 部署的目录名，完整的部署目录为${DIR}/${redis_dir_name}
redis_dir_name=redis

# 解压后的名字
FILE=redis-${redis_version}
# redis源码包名字
redis_tgz=${FILE}.tar.gz
########################################

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

function add_user_and_group(){
    if id -g ${1} >/dev/null 2>&1; then
        echo_warning ${1}组已存在，无需创建
    else
        groupadd ${1}
        echo_info 创建${1}组
    fi
    if id -u ${1} >/dev/null 2>&1; then
        echo_warning ${1}用户已存在，无需创建
    else
        useradd -M -g ${1} -s /sbin/nologin ${1}
        echo_info 创建${1}用户
    fi
}

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

add_user_and_group redis

# 如果同端口已被占用，则直接退出
netstat -tnlp | grep ${PORT}
if [ $? -eq 0 ];then
    echo_error ${PORT} 端口已被占用！退出
    exit 21
fi

download_tar_gz ${src_dir} http://download.redis.io/releases/${redis_tgz}
cd ${file_in_the_dir}
untar_tgz ${redis_tgz}

mv ${FILE} ${DIR}/${redis_dir_name}

cd ${DIR}/${redis_dir_name}
redis_home=$(pwd)

echo_info 检查编译环境
yum install -y gcc
yum install -y centos-release-scl-rh 
yum install -y devtoolset-9-gcc devtoolset-9-gcc-c++ devtoolset-9-binutils
# 升级gcc，6.x版本需要
source /opt/rh/devtoolset-9/enable

echo_info 编译redis
# 清理先前编译出错的内容
make distclean
multi_core_compile

echo_info 优化redis.conf文件
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


######################
echo_info 生成redis.service文件用于systemd控制

cat > /usr/lib/systemd/system/redis.service << EOF
[Unit]
Description=Redis
After=network.target

[Service]
User=redis
Group=redis
Type=forking
ExecStart=${redis_home}/src/redis-server ${redis_home}/redis.conf
ExecStop=${redis_home}/redis-shutdown
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo_info 设置停止redis脚本
cat > ${redis_home}/redis-shutdown << EOF
#!/bin/bash
#
# Wrapper to close properly redis and sentinel
test x"\$REDIS_DEBUG" != x && set -x

REDIS_CLI=${redis_home}/src/redis-cli

# Retrieve service name
SERVICE_NAME="\$1"
if [ -z "\$SERVICE_NAME" ]; then
   SERVICE_NAME=redis
fi

# Get the proper config file based on service name
CONFIG_FILE="${redis_home}/\$SERVICE_NAME.conf"

# Use awk to retrieve host, port from config file
HOST=$(awk '/^[[:blank:]]*bind/ { print \$2 }' \$CONFIG_FILE | tail -n1)
PORT=$(awk '/^[[:blank:]]*port/ { print \$2 }' \$CONFIG_FILE | tail -n1)
PASS=$(awk '/^[[:blank:]]*requirepass/ { print \$2 }' \$CONFIG_FILE | tail -n1)
SOCK=$(awk '/^[[:blank:]]*unixsocket\s/ { print \$2 }' \$CONFIG_FILE | tail -n1)

# Just in case, use default host, port
HOST=\${HOST:-127.0.0.1}
if [ "\$SERVICE_NAME" = redis ]; then
    PORT=\${PORT:-6379}
else
    PORT=\${PORT:-26739}
fi

# Setup additional parameters
# e.g password-protected redis instances
[ -z "\$PASS"  ] || ADDITIONAL_PARAMS="-a \$PASS"

# shutdown the service properly
if [ -e "\$SOCK" ] ; then
    \$REDIS_CLI -s \$SOCK \$ADDITIONAL_PARAMS shutdown
else
    \$REDIS_CLI -h \$HOST -p \$PORT \$ADDITIONAL_PARAMS shutdown
fi
EOF
chmod +x ${redis_home}/redis-shutdown

echo_info 添加环境变量
cat > /etc/profile.d/redis.sh << EOF
export PATH=$PATH:${redis_home}/src
EOF

chown -R redis:redis ${redis_home}
######################

echo_info 已编译成功，详细信息如下：
echo -e "\033[37m                  部署版本：  ${FILE}\033[0m"
echo -e "\033[37m                  监听IP：   ${listen_ip}\033[0m"
echo -e "\033[37m                  监听端口：  ${PORT}\033[0m"
echo -e "\033[37m                  redis密码：${redis_pass}\033[0m"

echo_info 启动redis
systemctl start redis

netstat -tnlp | grep ${PORT}
if [ $? -eq 0 ];then
    echo_info redis已成功启动！
    echo -e "\033[37m                  启动命令：systemctl start redis\033[0m"
    echo -e "\033[37m                  关闭命令：systemctl stop redis\033[0m"
    echo -e "\033[37m                  连接服务端：redis-cli\033[0m"
    echo -e "\033[37m                  部署版本：  ${FILE}\033[0m"
    echo_warning 由于bash特性限制，在本终端连接redis-server需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端连接redis-server
else
    echo_error 启动失败，请检查配置！
    exit 20
fi

echo_info iredis介绍：
echo -e "\033[37m                  iredis是一个具有代码补全和语法高亮的redis命令行客户端，github项目地址：\033[0m"
echo -e "\033[37m                  https://github.com/laixintao/iredis\033[0m"
function iredisyn() {
read -p "是否添加iredis (y/n)：" choice
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
