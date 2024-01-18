#!/bin/bash
git_version=2.36.0
download_dir=$(pwd)/00src00


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


# 版本号判断，只有比服务器已部署的版本号新，才进行升级
git --version &> /dev/null
if [ $? -eq 0 ];then
    git_old_version=$(git --version | awk '{print $3}')
else
    git_old_version=0
fi

# 比较版本号
latest_version=$(printf '%s\n%s\n' "$git_old_version" "$git_version" | sort -V | tail -n1)

if [[ ${latest_version} == ${git_old_version} ]];then
    echo_error "要升级的git版本号(${git_version})未高于服务器已部署的版本号(${git_old_version})，退出"
    exit 1
fi

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

# 多核编译，升级openssl定制版
function multi_core_compile(){
    for i in $(ls /etc/ld.so.conf.d/);do
        lib_path=$(cat /etc/ld.so.conf.d/$i | grep "openssl" | grep "lib" | grep -v "^#")
        if [[ ! -z $lib_path ]];then
            break
        fi
    done
    if [[ ! -z $lib_path ]];then
        make_cmd="make LDFLAGS='-L$lib_path -lssl -lcrypto'"
    else
        make_cmd="make"
    fi
    echo_info 多核编译
    assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
    cpucores=$(cat /proc/cpuinfo | grep -c processor)
    compilecore=$(($cpucores - $assumeused - 1))
    if [ $compilecore -ge 1 ];then
        $make_cmd -j $compilecore prefix=/usr/local/git all
        $make_cmd -j $compilecore prefix=/usr/local/git install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi
    else
        $make_cmd prefix=/usr/local/git all
        $make_cmd prefix=/usr/local/git install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi 
    fi
}


echo_info 安装依赖
gcc --version &> /dev/null
if [ $? -ne 0 ];then
    yum install -y gcc
fi
yum install -y perl-ExtUtils-MakeMaker curl-devel expat-devel gettext-devel openssl-devel zlib-devel asciidoc 

echo_info 移除旧版本git
yum remove git -y

echo_info 下载新版本git二进制包
download_tar_gz ${download_dir} https://mirrors.edge.kernel.org/pub/software/scm/git/git-${git_version}.tar.xz
cd ${file_in_the_dir}
untar_tgz git-${git_version}.tar.xz
cd git-${git_version}

echo_info 安装新版本git
multi_core_compile

# 清理
cd ${file_in_the_dir}
rm -rf git-${git_version}

echo "export PATH=$PATH:/usr/local/git/bin" >> /etc/profile
source /etc/profile
echo_info "git已更新：${git_old_version} --> ${git_version}"
echo_warning 由于bash特性限制，在本终端执行git命令需要先手动执行 source /etc/profile 加载环境变量，或者重新打开一个终端