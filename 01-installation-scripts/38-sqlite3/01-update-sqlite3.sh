#!/bin/bash
# 用于CentOS7升级自带的sqlite3

OLD_VERSION=$(sqlite3 -version | awk '{print $1}')
SQLITE_DOWNLOAD_URL="https://www.sqlite.org/2021/sqlite-autoconf-3370000.tar.gz"
SQLITE_TGZ_FILE=$(basename $SQLITE_DOWNLOAD_URL)
SQLITE_UNTGZ_DIR=$( echo ${SQLITE_TGZ_FILE} | awk -F'.' '{print $1}')
# 包下载目录
src_dir=$(pwd)/00src00

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
        exit 1
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
    if [ $http_code -ne 200 ];then
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
                    yum install -y wget
                fi
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

# 多核编译
function multi_core_compile(){
    echo_info 多核编译
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

OLD_VERSION_SEQ=$(echo ${OLD_VERSION} | tr -d ".")
NEW_VERSION_SEQ_PRE=$(echo ${SQLITE_UNTGZ_DIR} | awk -F "-" '{print $3}')
NEW_VERSION_SEQ=${NEW_VERSION_SEQ_PRE:0:4}

if [ ${OLD_VERSION_SEQ} -ge ${NEW_VERSION_SEQ} ];then
    echo_error "脚本中sqlite3的更新版本号(${NEW_VERSION_SEQ})未高于服务器已部署的版本号(${OLD_VERSION_SEQ})，请查看官网https://www.sqlite.org/download.html，修改脚本中的最新版本号"
    exit 1
fi

echo_info 安装编译工具
yum install -y gcc sqlite-devel

download_tar_gz ${src_dir} ${SQLITE_DOWNLOAD_URL}
cd ${file_in_the_dir}
untar_tgz ${SQLITE_TGZ_FILE}
cd ${SQLITE_UNTGZ_DIR}
./configure --prefix=/usr/local
multi_core_compile

echo_info 备份原文件至 /usr/bin/sqlite3_old
mv /usr/bin/sqlite3 /usr/bin/sqlite3_old

ln -s /usr/local/bin/sqlite3 /usr/bin/sqlite3
echo "/usr/local/lib" > /etc/ld.so.conf.d/sqlite3.conf
ldconfig

echo_info 清理临时文件
cd ~
rm -rf ${src_dir}/${SQLITE_UNTGZ_DIR}

NEW_VERSION=$(sqlite3 -version | awk '{print $1}')

echo_info "sqlite3已更新：${OLD_VERSION} --> ${NEW_VERSION}"