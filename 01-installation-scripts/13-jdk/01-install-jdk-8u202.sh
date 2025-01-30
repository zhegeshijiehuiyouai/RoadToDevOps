#!/bin/bash
#
# 8u202为最后一个免费版
# 说明：如果下载速度慢，可先将rpm包下载下来，移动至和该脚本同一目录，然后再执行该脚本
#

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
	echo_error 不支持的操作系统
	exit 99
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
function download_tar_gz(){
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IksS $2 | head -1 | awk '{print $2}')
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
                if [[ $os == "centos" ]];then
                    yum install -y wget
                elif [[ $os == "ubuntu" ]];then
                    apt install -y wget
                elif [[ $os == 'rocky' || $os == 'alma' ]];then
                    dnf install -y wget
                fi
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
                    if [[ $os == "centos" ]];then
                        yum install -y wget
                    elif [[ $os == "ubuntu" ]];then
                        apt install -y wget
                    elif [[ $os == 'rocky' || $os == 'alma' ]];then
                        dnf install -y wget
                    fi
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

function jdk_install_centos() {
    # download_tar_gz $src_dir https://github.com/frekele/oracle-java/releases/download/8u202-b08/jdk-8u202-linux-x64.rpm
    # github加速节点下载
    download_tar_gz $src_dir https://cors.isteed.cc/https://github.com/frekele/oracle-java/releases/download/8u202-b08/jdk-8u202-linux-x64.rpm

    cd ${file_in_the_dir}
    rpm -Uvh jdk-8u202-linux-x64.rpm
    if [ $? -ne 0 ];then
        echo_error jdk安装失败，请检查rpm包是否下载完全。建议手动下载后，覆盖服务器上的rpm包
        exit 1
    fi
    set_env /usr/java/jdk1.8.0_202-amd64
    source /etc/profile
}

function jdk_install_ubuntu() {
    download_tar_gz $src_dir https://cors.isteed.cc/https://github.com/frekele/oracle-java/releases/download/8u202-b08/jdk-8u202-linux-x64.tar.gz
    cd ${file_in_the_dir}
    untar_tgz jdk-8u202-linux-x64.tar.gz
    [ -d /usr/java/jdk1.8.0_202 ] && rm -rf /usr/java/jdk1.8.0_202
    mkdir -p /usr/java
    mv jdk1.8.0_202 /usr/java/
    set_env /usr/java/jdk1.8.0_202
    source /etc/profile
    echo_info 设置默认jdk
    update-alternatives --install /usr/bin/java java /usr/java/jdk1.8.0_202/bin/java 300  
    update-alternatives --install /usr/bin/javac javac /usr/java/jdk1.8.0_202/bin/javac 300  
    update-alternatives --install /usr/bin/jar jar /usr/java/jdk1.8.0_202/bin/jar 300   
    update-alternatives --install /usr/bin/javah javah /usr/java/jdk1.8.0_202/bin/javah 300   
    update-alternatives --install /usr/bin/javap javap /usr/java/jdk1.8.0_202/bin/javap 300
    latest_ubuntu_version=$(echo -e "${os_version}\n22.04" | sort -V -r | head -1)
    # 22.04及之前的版本使用下面的方法
    if [[ $latest_ubuntu_version == 22.04 ]];then
        update-alternatives --config java
    # 24.04及之后
    else
        echo 1 | update-alternatives --config java
        echo
        echo_info 选择1，手动模式
    fi
}



######################################
pre_install_check
if [[ $os == 'centos' || $os == 'rocky' || $os == 'alma' ]];then
    jdk_install_centos
elif [[ $os == 'ubuntu' ]];then
    jdk_install_ubuntu
fi
echo_info jdk已安装成功，版本信息如下
java -version