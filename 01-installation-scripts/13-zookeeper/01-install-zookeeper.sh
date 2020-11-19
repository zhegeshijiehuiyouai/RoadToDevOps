#!/bin/bash

# zookeeper版本，鉴于仓库中3.5.x或者3.6.x只会保留一个版本，因此这里不指定第三位x的版本号，转而从网络获取
zk_version=3.5
# 不要移动到后面去
zk_exact_version=$(curl -s --connect-timeout 3 http://mirrors.aliyun.com/apache/zookeeper/ | grep zookeeper-${zk_version} | awk -F'"' '{print $2}' | xargs basename | awk -F'-' '{print $2}')
# 接口正常，[ ! ${zk_exact_version} ]为1；接口失败，[ ! ${zk_exact_version} ]为0
if [ ! ${zk_exact_version} ];then
    echo -e "\033[31m[*] zookeeper仓库[ \033[36mhttp://mirrors.aliyun.com/apache/zookeeper/\033[31m ]访问超时，请检查网络！\033[0m"
    exit 2
fi

# 包下载目录
src_dir=$(pwd)/00src00
# 部署目录的父目录，比如要部署到/data/zookeeper，那么basedir就是/data
basedir=/data
# 就是上面注释中的zookeeper，完整部署目录为${basedir}/${zookeeperdir}
zookeeperdir=zookeeper-${zk_exact_version}
# 端口
zk_port=2181
# 启动服务的用户
sys_user=zookeeper


java -version &> /dev/null
if [ $? -ne 0 ];then
    echo -e "\033[31m[*] 未检测到java，请先部署java\033[0m"
    exit 1
fi

# 解压
function untar_tgz(){
    echo -e "\033[32m[+] 解压 $1 中\033[0m"
    tar xf $1
    if [ $? -ne 0 ];then
        echo -e "\033[31m[*] 解压出错，请检查!\033[0m"
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
    # 检测是否有wget工具
    if [ ! -f /usr/bin/wget ];then
        echo -e "\033[32m[+] 安装wget工具\033[0m"
        yum install -y wget
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
            echo -e "\033[32m[+] 下载 $download_file_name 至 $(pwd)/\033[0m"
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
                echo -e "\033[32m[+] 下载 $download_file_name 至 $(pwd)/\033[0m"
                wget $3
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            else
                # 进入此处，表示${src_dir}目录内有压缩包
                echo -e "\033[32m[!] 发现压缩包$(pwd)/$download_file_name\033[0m"
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            fi
        fi
    else
        # 进入此处表示脚本所在目录有压缩包
        echo -e "\033[32m[!] 发现压缩包$(pwd)/$download_file_name\033[0m"
        file_in_the_dir=$(pwd)
    fi
}

function add_user_and_group(){
    if id -g ${1} >/dev/null 2>&1; then
        echo -e "\033[32m[#] ${1}组已存在，无需创建\033[0m"
    else
        groupadd ${1}
        echo -e "\033[32m[+] 创建${1}组\033[0m"
    fi
    if id -u ${1} >/dev/null 2>&1; then
        echo -e "\033[32m[#] ${1}用户已存在，无需创建\033[0m"
    else
        useradd -M -g ${1} -s /sbin/nologin ${1}
        echo -e "\033[32m[+] 创建${1}用户\033[0m"
    fi
}



add_user_and_group ${sys_user}
download_tar_gz ${src_dir} http://mirrors.aliyun.com/apache/zookeeper/zookeeper-${zk_exact_version}/apache-zookeeper-${zk_exact_version}-bin.tar.gz
cd ${file_in_the_dir}
untar_tgz apache-zookeeper-${zk_exact_version}-bin.tar.gz

echo -e "\033[32m[>] 检测部署目录中\033[0m"
if [ -d ${basedir}/${zookeeperdir} ];then
    echo -e "\033[31m[*] 目录 ${basedir}/${zookeeperdir} 已存在，无法继续安装，退出\033[0m"
    exit 3
else
    [ -d ${basedir} ] || mkdir -p ${basedir}
fi

mv apache-zookeeper-${zk_exact_version}-bin ${basedir}/${zookeeperdir}
mkdir -p ${basedir}/${zookeeperdir}/{data,logs}
cd ${basedir}/${zookeeperdir}

cp conf/zoo_sample.cfg conf/zoo.cfg
cat > /tmp/zookeeper_install_temp_$(date +%F).sh <<EOF
sed -i 's#^dataDir=.*#dataDir=${basedir}/${zookeeperdir}/data#g' conf/zoo.cfg
sed -i 's#^clientPort=.*#clientPort=${zk_port}#g' conf/zoo.cfg
EOF

/bin/bash /tmp/zookeeper_install_temp_$(date +%F).sh
rm -rf /tmp/zookeeper_install_temp_$(date +%F).sh

echo -e "\033[32m[>] 部署目录授权中\033[0m"
chown -R ${sys_user}:${sys_user} ${basedir}/${zookeeperdir}

echo -e "\033[32m[+] 生成/usr/lib/systemd/system/zookeeper.service\033[0m"
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

[Install]
WantedBy=multi-user.target

EOF

systemctl daemon-reload
systemctl start zookeeper
if [ $? -ne 0 ];then
    echo -e "\033[31m[*] zookeeper启动出错，请检查！\033[0m"
    exit 4
fi
systemctl enable zookeeper &> /dev/null

echo -e "\033[36m[#] zookeeper 已安装配置完成：\033[0m"
echo -e "\033[36m    部署目录：${basedir}/${zookeeperdir}\033[0m"
echo -e "\033[36m    启动命令：systemctl start zookeeper\033[0m"

