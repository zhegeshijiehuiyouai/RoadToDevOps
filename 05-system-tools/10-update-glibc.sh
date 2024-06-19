#!/bin/bash

glibc_new_version=2.28
src_dir=$(pwd)/00src00
mydir=$(pwd)

# 获取glibc老版本
glibc_old_version=$(ldd --version | head -1 | awk '{print $NF}')

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

# 比较版本号
latest_version=$(printf '%s\n%s\n' "$glibc_old_version" "$glibc_new_version" | sort -V | tail -n1)

if [[ ${latest_version} == ${glibc_old_version} ]];then
    echo_error "升级版本（${glibc_new_version}）小于等于已安装版本（${glibc_old_version}），请查看网址http://mirrors.cloud.tencent.com/gnu/glibc/ 获取最新版本，并修改脚本中的最新版本号"
    exit 1
fi

function user_confirm() {
    read -e user_confirm_input
    case $user_confirm_input in
    y|Y)
        true
        ;;
    n|N)
        echo_info 用户取消
        exit 0
        ;;
    *)
        user_confirm
        ;;
    esac
}

##################################### 主程序

echo_warning "请确保您知道升级glibc的风险，并已备份系统，否则请退出脚本！！！是否继续[y/n]"
user_confirm

function install_confirm() {
    read -e install_confirm_input
    case $install_confirm_input in
    y|Y)
        true
        ;;
    n|N)
        exit 0
        ;;
    *)
        echo_warning 请输入y或n
        install_confirm
        ;;
    esac
}
echo_warning "glibc版本将从 ${glibc_old_version} 升级到 ${glibc_new_version} ，是否继续[y/n]"
install_confirm

# 版本检测，升级glibc，对于版本的要求有点严格，不匹配的话很可能升级失败。
gcc_version=$(gcc --version | head -1 | awk '{print $3}')
make_version=$(make --version | head -1 | awk '{print $3}')

if [[ $glibc_new_version == "2.28" ]];then
    gcc_main_version=$(echo $gcc_version | awk -F'.' '{print $1}')
    if [ $gcc_main_version -ge 11 ];then
        echo_warning "当前gcc版本为${gcc_version}，使用该版本的gcc升级glibc到${glibc_new_version}版本大概率会出错"
        user_confirm
    elif [[ $gcc_version != "8.2.0" ]];then
        echo_warning 升级glibc需要的gcc版本：4.9或更高版本
        echo_warning 推荐版本：8.2.0
        echo_warning 当前版本：$gcc_version
        user_confirm
    fi
    if [[ $make_version != "4.2.1" ]];then
        echo_warning 升级glibc需要的make版本：4.0或更高版本
        echo_warning 推荐版本：4.2.1
        echo_warning 当前版本：$make_version
        user_confirm
    fi
    python_version=$(python --version 2>&1 | awk '{print $2}')
    newest_python_version=$(printf '%s\n%s\n' "$python_version" "3.4" | sort -V | tail -n1)
    if [[ $newest_python_version != $python_version ]];then
        echo_warning 升级glibc需要的python版本：3.4或更高版本
        echo_warning 当前版本：$python_version
        user_confirm
    fi
fi

download_tar_gz ${src_dir} http://mirrors.cloud.tencent.com/gnu/glibc/glibc-${glibc_new_version}.tar.gz
cd ${file_in_the_dir}
untar_tgz glibc-${glibc_new_version}.tar.gz
cd glibc-${glibc_new_version}
echo_info 调整测试文件
test_file=scripts/test-installation.pl
if grep -q '"nss_test2"' $test_file; then
    true
else
    if grep -q 'ne "nss_test1"' $test_file; then
        # 将ne "nss_test1"替换为ne "nss_test1" && ne "nss_test2"，这样做是因为服务器上几乎都没有nss_test2这个库，直接跳过这个的测试
        sed -i 's/\$name ne \"nss_test1\"/\$name ne \"nss_test1\" \&\& \$name ne \"nss_test2\"/g' $test_file
    fi
fi

mkdir build
cd build
../configure --prefix=/usr --enable-add-ons --disable-profile --disable-multi-arch --enable-obsolete-nsl
multi_core_compile


# 修复升级glibc后中文乱码问题
echo_info 更新locale相关文件
# 利用multi_core_compile中的变量
if [ $compilecore -ge 1 ];then
    make -j $compilecore localedata/install-locales
    if [ $? -ne 0 ];then
        echo_error 编译安装出错，请检查脚本
        exit 1
    fi
else
    make localedata/install-locales
    if [ $? -ne 0 ];then
        echo_error 编译安装出错，请检查脚本
        exit 1
    fi 
fi

echo_info glibc安装完毕，版本：${glibc_new_version}


