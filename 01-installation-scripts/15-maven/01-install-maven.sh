#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
version=3.6.3

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

# 解压
function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
        exit 2
    fi
}

############ 开始 ############
if [ -d maven ];then
    echo_error $(pwd)/maven 目录已存在，退出
    exit 1
fi

download_tar_gz $src_dir https://mirrors.tuna.tsinghua.edu.cn/apache/maven/maven-3/${version}/binaries/apache-maven-${version}-bin.tar.gz

cd ${file_in_the_dir}
untar_tgz apache-maven-${version}-bin.tar.gz

echo_info 重命名maven目录为 ${back_dir}/maven
mv apache-maven-${version} ${back_dir}/maven

echo_info 配置环境变量
echo "export MAVEN_HOME=${back_dir}/maven" >  /etc/profile.d/maven.sh
echo "export PATH=\$PATH:${back_dir}/maven/bin" >> /etc/profile.d/maven.sh

echo_info 创建本地仓库目录
mkdir -p ${back_dir}/maven/repository

echo_info 配置本地仓库
sed -i '/  <!-- localRepository/i\  <localRepository>'${back_dir}'/maven/repository</localRepository>' ${back_dir}/maven/conf/settings.xml
# sed -i '/  <!-- localRepository/i\  <updatePolicy>always</updatePolicy>' ${back_dir}/maven/conf/settings.xml

echo_info 配置仓库镜像地址
cat > /tmp/.temp_repo_file <<EOF
	<mirror>
	 <id>alimaven</id>
	 <name>aliyun maven</name>
	 <url>http://maven.aliyun.com/nexus/content/groups/public/</url>
	 <mirrorOf>central</mirrorOf>
	</mirror> 
EOF
sed -i '/\s<mirrors>/ r /tmp/.temp_repo_file' ${back_dir}/maven/conf/settings.xml
rm -f /tmp/.temp_repo_file

echo_warning 由于bash特性限制，在本终端使用 mvn 命令，需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端连接mongodb
echo_info maven已部署完毕，版本信息如下：
source /etc/profile
mvn -version