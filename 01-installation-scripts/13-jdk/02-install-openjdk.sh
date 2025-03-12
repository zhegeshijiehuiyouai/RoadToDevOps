#!/bin/bash
# 通用openjdk安装脚本，支持11之后的openjdk安装，jdk8的话，推荐最后一个免费的oracle jdk8，8u202


# 包下载目录
src_dir=$(pwd)/00src00
# 工作目录
work_dir=$(pwd)
# 提供几个openjdk下载地址，根据自己喜好，在install_main_func函数中修改下载链接：
# openjdk官网：https://openjdk.org/projects/jdk-updates/
# adoptium的github，上面官网其实导向了这里。切换版本的话，直接修改链接中的数字：https://github.com/adoptium/temurin17-binaries/releases
# 清华的Adoptium镜像：https://mirrors.tuna.tsinghua.edu.cn/Adoptium/
# 微软构建的：https://www.microsoft.com/openjdk
# 红帽构建的：https://developers.redhat.com/products/openjdk/download

# 镜像加速地址
mirror_url=https://cors.isteed.cc/

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

# 脚本执行用户检测
if [[ $(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

# 检测操作系统
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
    # 阻止配置更新弹窗
    export UCF_FORCE_CONFFOLD=1
    # 阻止应用重启弹窗
    export NEEDRESTART_SUSPEND=1
elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)
elif [[ -e /etc/almalinux-release ]]; then
    os="alma"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/almalinux-release)
else
    # 本次安装脚本通用，不用退出
	# echo_error 不支持的操作系统
	# exit 99
    true
fi

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
function check_downloadfile() {
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IksS $1 | head -1 | awk '{print $2}')
    if [ $http_code -eq 404 ];then
        echo_error $1
        echo_error 服务端文件不存在，退出
        exit 98
    fi
}
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
                if [[ $os == "centos" ]];then
                    yum install -y wget
                elif [[ $os == "ubuntu" ]];then
                    apt install -y wget
                elif [[ $os == 'rocky' || $os == 'alma' ]];then
                    dnf install -y wget
                fi
            fi
            check_downloadfile $2
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
                    if [[ $os == "centos" ]];then
                        yum install -y wget
                    elif [[ $os == "ubuntu" ]];then
                        apt install -y wget
                    elif [[ $os == 'rocky' || $os == 'alma' ]];then
                        dnf install -y wget
                    fi
                fi
                check_downloadfile $2
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

# 解压
function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
        exit 80
    fi
}

function pre_install_check() {
    java -version &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到java命令，退出
        exit 2
    fi
}

function folder_check() {
    if [ -d $1 ];then
        echo_error 检测到目录 $1，请确认是否重复安装
        exit 1
    fi
}

function set_env() {
    echo_info 配置环境变量
    cat > /etc/profile.d/java.sh << EOF
#set java environment
export JAVA_HOME=$1
export JRE_HOME=\${JAVA_HOME}/jre
export JAVA_BIN=\${JAVA_HOME}/bin
export CLASSPATH=.:\${JAVA_HOME}/lib:\${JRE_HOME}/lib  
export PATH=\${JAVA_HOME}/bin:\$PATH  
EOF
}

function install_openjdk() {
    # download_tar_gz $src_dir https://github.com/frekele/oracle-java/releases/download/8u202-b08/jdk-8u202-linux-x64.rpm
    # github加速节点下载
    download_tar_gz $src_dir ${openjkd_download_url}

    cd ${file_in_the_dir}
    untar_tgz ${tgz_file}
    mv ${openjdk_folder} ${work_dir}/${openjdk_folder}
    set_env ${work_dir}/${openjdk_folder}
    source /etc/profile
    echo_info jdk已安装成功，版本信息如下
    java -version
    echo_warning 由于bash特性限制，在本终端执行java命令需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端之后再执行java命令
}

function install_main_func(){
    pre_install_check
    echo_info '请输入要安装的OpenJDK版本。举例：安装OpenJDK 17，那么输入 17'
    read -p "请输入：" -e user_input_install_version
    case $user_input_install_version in
        11)
            tgz_file=OpenJDK11U-jdk_x64_linux_hotspot_11.0.26_4.tar.gz
            openjkd_download_url=${mirror_url}https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.26%2B4/${tgz_file}
            openjdk_folder=jdk-11.0.26+4
            ;;
        17)
            tgz_file=OpenJDK17U-jdk_x64_linux_hotspot_17.0.14_7.tar.gz
            openjkd_download_url=${mirror_url}https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.14%2B7/${tgz_file}
            openjdk_folder=jdk-17.0.14+7
            ;;
        21)
            tgz_file=OpenJDK21U-jdk_x64_linux_hotspot_21.0.6_7.tar.gz
            openjkd_download_url=${mirror_url}https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.6%2B7/${tgz_file}
            openjdk_folder=jdk-21.0.6+7
            ;;
        *)
            echo_warning "仅支持安装以下LTS版本："
            echo "11、17、21"
            sleep 1
            install_main_func
            ;;
    esac
    folder_check ${openjdk_folder}
    install_openjdk
}


######################################

install_main_func

