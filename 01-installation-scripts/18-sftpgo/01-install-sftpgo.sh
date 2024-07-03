#!/bin/bash

sftpgo_version=2.6.0
src_dir=$(pwd)/00src00      # 安装包下载地址
sftp_home=$(pwd)/sftpgo
data_dir=${sftp_home}/data  # 数据目录
backup_dir=${sftp_home}/backup  # 备份目录
log_dir=${sftp_home}/log   # 日志目录
db_dir=${sftp_home}/db      # 使用sqlite作为存储时，数据库文件的目录
sftp_port=2222              # sftp端口
http_port=8088              # web界面端口


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

#-------------------------------------------------
function input_machine_ip_fun() {
    read input_machine_ip
    machine_ip=${input_machine_ip}
    if [[ ! $machine_ip =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
        echo_error 错误的ip格式，退出
        exit 1
    fi
}
function get_machine_ip() {
    ip a | grep -E "bond" &> /dev/null
    if [ $? -eq 0 ];then
        echo_warning 检测到绑定网卡（bond），请手动输入使用的 ip ：
        input_machine_ip_fun
    elif [ $(ip a | grep -E "inet.*e(ns|np|th).*[[:digit:]]+.*" | awk '{print $2}' | cut -d / -f 1 | wc -l) -gt 1 ];then
        echo_warning 检测到多个 ip，请手动输入使用的 ip ：
        input_machine_ip_fun
    else
        machine_ip=$(ip a | grep -E "inet.*e(ns|np|th).*[[:digit:]]+.*" | awk '{print $2}' | cut -d / -f 1)
    fi
}
#-------------------------------------------------

if [ -d /etc/sftpgo ];then
    echo_error 检测到/etc/sftpgo目录，请确认是否重复安装了
    exit 2
fi

echo_info 安装依赖工具
if [[ $os == "centos" ]];then
    yum install -y jq net-tools
elif [[ $os == "ubuntu" ]];then
    apt install -y jq net-tools
elif [[ $os == 'rocky' ]];then
    dnf install -y jq net-tools
fi

# 如果同端口已被占用，则直接退出
netstat -tnlp | grep ${sftp_port}
if [ $? -eq 0 ];then
    echo_error ${sftp_port} 端口已被占用！退出
    exit 21
fi
netstat -tnlp | grep ${http_port}
if [ $? -eq 0 ];then
    echo_error ${http_port} 端口已被占用！退出
    exit 21
fi

if [[ $os == "centos" || $os == 'rocky' ]];then
    # 使用github加速节点下载
    download_tar_gz $src_dir https://gh.con.sh/https://github.com/drakkan/sftpgo/releases/download/v${sftpgo_version}/sftpgo-${sftpgo_version}-1.x86_64.rpm
    cd $file_in_the_dir
    echo_info 安装sftpgo
    if [[ $os == 'centos' ]];then
        yum localinstall -y sftpgo-${sftpgo_version}-1.x86_64.rpm
    elif [[ $os == 'rocky' ]];then
        dnf localinstall -y sftpgo-${sftpgo_version}-1.x86_64.rpm
    fi
elif [[ $os=="ubuntu" ]];then 
    download_tar_gz $src_dir https://gh.con.sh/https://github.com/drakkan/sftpgo/releases/download/v${sftpgo_version}/sftpgo_${sftpgo_version}-1_amd64.deb
    cd $file_in_the_dir
    echo_info 安装sftpgo
    apt install -y ./sftpgo_${sftpgo_version}-1_amd64.deb
    if [ ! -d /etc/sftpgo ];then
        # 可能之前存在sftpggo，只删除了/etc/sftpgo文件，没有卸载
        apt purge -y sftpgo
        apt install -y ./sftpgo_${sftpgo_version}-1_amd64.deb
        # 还没有这个目录的话就是安装失败了
        if [ ! -d /etc/sftpgo ];then
            echo_error sftpgo安装失败，请检测服务器环境
            exit 3
        fi
    fi
fi


# 下面的操作看起来很傻，不过如果修改了最开始的变量，那么这个就很有用了
mkdir -p $data_dir
mkdir -p $backup_dir
mkdir -p $log_dir
mkdir -p $db_dir
function chown_func() {
    chown -R sftpgo:sftpgo /etc/sftpgo
    chown -R sftpgo:sftpgo $sftp_home
    chown -R sftpgo:sftpgo $data_dir
    chown -R sftpgo:sftpgo $backup_dir
    chown -R sftpgo:sftpgo $log_dir
    chown -R sftpgo:sftpgo $db_dir
}
chown_func

cd /etc/sftpgo
if [ ! -f sftpgo.json.default ];then
    echo_info 备份默认配置
    cp -a sftpgo.json sftpgo.json.default
fi

echo_info 更新sftpgo配置
get_machine_ip
temp_file=tempfile_$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
jq --arg db_dir $db_dir --arg data_dir $data_dir --arg backup_dir $backup_dir --arg sftp_port $sftp_port --arg http_port $http_port '.data_provider.name = $db_dir + "/sftpgo.db" | .data_provider.users_base_dir = $data_dir | .data_provider.backups_path = $backup_dir | .sftpd.bindings[].port = ($sftp_port | tonumber) | .httpd.bindings[].port = ($http_port | tonumber)'  sftpgo.json > ${temp_file}
cat ${temp_file} > sftpgo.json
rm -f ${temp_file}

cat > sftpgo.env << __EOF__
SFTPGO_LOG_FILE_PATH=${log_dir}/sftpgo.log
# 支持的日志级别包括 debug、info、warn、error
SFTPGO_LOG_LEVEL=info
SFTPGO_SFTPD__LOGIN_BANNER_FILE=/etc/sftpgo/LOGIN_BANNER_FILE
__EOF__
cat > LOGIN_BANNER_FILE << __EOF__
### SFTPGO ON ${machine_ip} ###
__EOF__
chown_func

echo_info 初始化
sftpgo initprovider
chown_func
echo_info 启动sftpgo
systemctl restart sftpgo
# ubuntu安装完后会自己启动，就会产生这些文件，删除
[ -d /var/lib/sftpgo ] && rm -rf /var/lib/sftpgo
[ -d /srv/sftpgo ] && rm -rf /srv/sftpgo


echo_info sftpgo已部署，请前往管理界面创建admin账号
echo_info 地址：http://${machine_ip}:${http_port}/web/admin/login
echo_info
echo_info 启动命令：systemctl start sftpgo