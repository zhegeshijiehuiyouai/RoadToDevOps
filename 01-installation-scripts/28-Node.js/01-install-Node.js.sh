#!/bin/bash

# nodejs_version=v$(curl -s https://nodejs.org/zh-cn/download/ | grep "长期维护版" | awk -F'<strong>' '{print $2}' | awk -F'</strong>' '{print $1}')
nodejs_version=v16.15.0
src_dir=$(pwd)/00src00
mydir=$(pwd)


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

function check_nodejs_dir() {
    if [ -d ${mydir}/node-${nodejs_version} ];then
        echo_error 检测到目录${mydir}/node-${nodejs_version}，请检查是否重复安装，退出
        exit 1
    fi
}

function main() {
    check_nodejs_dir
    # download_tar_gz ${src_dir} https://nodejs.org/dist/${nodejs_version}/node-${nodejs_version}-linux-x64.tar.xz
    download_tar_gz ${src_dir} https://nodejs.org/download/release/${nodejs_version}/node-${nodejs_version}-linux-x64.tar.xz
    cd ${file_in_the_dir}
    untar_tgz node-${nodejs_version}-linux-x64.tar.xz
    mv node-${nodejs_version}-linux-x64 ${mydir}/node-${nodejs_version}

    echo_info 设置环境变量
    echo "export PATH=\$PATH:${mydir}/node-${nodejs_version}/bin" > /etc/profile.d/nodejs.sh

    echo_info 配置环境变量
    echo "export NODE_HOME=${mydir}/node-${nodejs_version}" > /etc/profile.d/nodejs.sh
    echo "export PATH=\$PATH:${mydir}/node-${nodejs_version}/bin" >> /etc/profile.d/nodejs.sh
    source /etc/profile

    echo_info 配置镜像
    npm config set registry=https://registry.npmmirror.com/

    echo_info npm部署yarn
    npm install -g yarn

    echo_warning 由于bash特性限制，在本终端使用 node 等命令，需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端
  

    echo_info Node.js已部署完毕，部署目录：${mydir}/node-${nodejs_version}
    echo_info node版本
    node -v
    echo_info npm版本
    npm -v
    echo_info yarn版本
    yarn -v
}

main