#!/bin/bash

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

###########################################################################
# zookeeper版本，鉴于仓库中3.5.x或者3.6.x只会保留一个版本，因此这里不指定第三位x的版本号，转而从网络获取
zk_version=3.9
# 尽管不美观，但不要移动到后面去
curl_timeout=2
# 设置dns超时时间，避免没网情况下等很久
echo "options timeout:${curl_timeout} attempts:1 rotate" >> /etc/resolv.conf
zk_exact_version=$(curl -s --connect-timeout ${curl_timeout} http://mirrors.aliyun.com/apache/zookeeper/ | grep zookeeper-${zk_version} | awk -F'"' '{print $4}' | xargs basename | awk -F'-' '{print $2}')
# 接口正常，[ ! ${zk_exact_version} ]为1；接口失败，[ ! ${zk_exact_version} ]为0
if [ ! ${zk_exact_version} ];then
    echo_error zookeeper仓库[ http://mirrors.aliyun.com/apache/zookeeper/ ]访问超时，请检查网络！
    sed -i '$d' /etc/resolv.conf
    exit 2
fi
sed -i '$d' /etc/resolv.conf

# 包下载目录
src_dir=$(pwd)/00src00
# 部署目录的父目录，比如要部署到/data/zookeeper，那么basedir就是/data
basedir=$(pwd)
# 就是上面注释中的zookeeper，完整部署目录为${basedir}/${zookeeperdir}
zookeeperdir=zookeeper-${zk_exact_version}
# 端口
zk_port=2181
# 启动服务的用户
sys_user=zookeeper


# 脚本执行用户检测
if [[ $(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

# 检测操作系统
# $os_version变量并不总是存在，但为了方便，仍然保留这个变量
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	# os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)

else
	echo_error 不支持的操作系统
	exit 99
fi


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
                if [[ $os == "centos" ]];then
                    yum install -y wget
                elif [[ $os == "ubuntu" ]];then
                    apt install -y wget
                elif [[ $os == "rocky" ]];then
                    dnf install -y wget
                fi
            fi
            wget $2
            if [ $? -ne 0 ];then
                echo_error 下载 $2 失败！
                exit 80
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
                    elif [[ $os == "rocky" ]];then
                        dnf install -y wget
                    fi
                fi
                wget $2
                if [ $? -ne 0 ];then
                    echo_error 下载 $2 失败！
                    exit 80
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


########【注意】集群部署函数从这个函数里根据行数取内容，如果这里修改了行数，需要修改集群函数
function install_single_zk(){
    java -version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到java，请先部署java
        exit 1
    fi

    echo_info 检测部署目录中
    if [ -d ${basedir}/${zookeeperdir} ];then
        echo_error 目录 ${basedir}/${zookeeperdir} 已存在，无法继续安装，退出
        exit 3
    else
        [ -d ${basedir} ] || mkdir -p ${basedir}
    fi
    add_user_and_group ${sys_user}
    download_tar_gz ${src_dir} http://mirrors.aliyun.com/apache/zookeeper/zookeeper-${zk_exact_version}/apache-zookeeper-${zk_exact_version}-bin.tar.gz
    cd ${file_in_the_dir}
    untar_tgz apache-zookeeper-${zk_exact_version}-bin.tar.gz

    mv apache-zookeeper-${zk_exact_version}-bin ${basedir}/${zookeeperdir}
    mkdir -p ${basedir}/${zookeeperdir}/{data,logs}
    cd ${basedir}/${zookeeperdir}   

    cp conf/zoo_sample.cfg conf/zoo.cfg
    sed -i 's#^dataDir=.*#dataDir='${basedir}'/'${zookeeperdir}'/data#g' conf/zoo.cfg
    sed -i 's#^clientPort=.*#clientPort='${zk_port}'#g' conf/zoo.cfg
    # 3.5版本以后，zookeeper会多一个8080端口，没什么用，把它禁用掉
    # 当前版本小于3.5，下面的值为0
    port8080toggle=$(awk -v version=3.5 -v currentversion=${zk_version} 'BEGIN{print(version>currentversion)?"0":"1"}')
    if [ $port8080toggle -ne 0 ];then
        echo "admin.enableServer=false" >> conf/zoo.cfg
    fi
    # 开启四字命令
    echo "4lw.commands.whitelist=*" >> conf/zoo.cfg

    echo_info 部署目录授权中
    chown -R ${sys_user}:${sys_user} ${basedir}/${zookeeperdir}

    echo_info 配置环境变量
    echo "export ZOOKEEPER_HOME=${basedir}/${zookeeperdir}" >  /etc/profile.d/zookeeper.sh
    echo "export PATH=\$PATH:${basedir}/${zookeeperdir}/bin" >> /etc/profile.d/zookeeper.sh
    echo_warning 由于bash特性限制，在本终端使用 zkCli 等命令，需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端连接zookeeper

    echo_info 生成zookeeper.service文件用于systemd控制

cat >/usr/lib/systemd/system/zookeeper.service <<EOF
[Unit]
Description=Zookeeper server manager

[Service]
User=zookeeper
Group=zookeeper
Type=forking
ExecStart=${basedir}/${zookeeperdir}/bin/zkServer.sh start
ExecStop=${basedir}/${zookeeperdir}/bin/zkServer.sh stop
ExecReload=${basedir}/${zookeeperdir}/bin/zkServer.sh restart
Restart=always

[Install]
WantedBy=multi-user.target

EOF

    systemctl daemon-reload
    systemctl start zookeeper
    if [ $? -ne 0 ];then
        echo_error zookeeper启动出错，请检查！
        exit 4
    fi
    systemctl enable zookeeper &> /dev/null

    echo_info zookeeper 已安装配置完成：
    echo -e "\033[37m                  部署目录：${basedir}/${zookeeperdir}\033[0m"
    echo -e "\033[37m                  启动命令：systemctl start zookeeper\033[0m"

}

install_single_zk