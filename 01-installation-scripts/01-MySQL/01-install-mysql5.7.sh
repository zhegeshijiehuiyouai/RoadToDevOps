#!/bin/bash

# 脚本功能：自动部署mysql5.7
# 测试系统：CentOS7.9 、ubuntu 22.04
# mysql安装文件：二进制包
#
# mysql下载地址：https://cdn.mysql.com/Downloads/MySQL-5.7/mysql-5.7.33-linux-glibc2.12-x86_64.tar.gz
# 或者官网下载
#
# 将本脚本和二进制包放在同一目录下，脚本会在本目录下创建mysql作为mysql安装目录
#
# 本脚本默认会下载二进制包，如果自己上传，可以注释掉


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

#######################定义变量##############################
# 包下载目录
src_dir=$(pwd)/00src00
# 端口
PORT=3306
# mysql部署好后，root的默认密码
# 仅centos有效，ubuntu需要交互式的手动输入root密码
my_root_passwd=123456
# mysql版本
mysql_version=5.7.38

# 部署目录的父目录
DIR=$(pwd)
# 部署目录的名字，最终的部署目录为${DIR}/${mysql_dir_name}
mysql_dir_name=mysql-${mysql_version}


# 脚本执行用户检测
if [[ $(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

# 检测操作系统
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
elif [[ -e /etc/centos-release ]]; then
	os="centos"
	os_version=$(grep -oE '[0-9]+\.?.*\s' /etc/centos-release)
else
	echo_error 不支持的操作系统
	exit 99
fi

if [[ $os == 'centos' ]];then
    # mysql二进制包名字
    mysql_tgz=mysql-${mysql_version}-linux-glibc2.12-x86_64.tar.gz
    unit_file_name=mysqld.service
elif [[ $os == 'ubuntu' ]];then
    unit_file_name=mysql.service
fi
#############################################################

# 解压
function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
        exit 80
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
                    yum install -y wget
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

function init_account(){
    login_pass=$1

    systemctl enable ${unit_file_name} >/dev/null 2>&1
    systemctl start ${unit_file_name}
    # mysql启动失败的话退出
    if [ $? -ne 0 ];then
        echo_error mysql启动失败，请查看错误信息
        exit 81
    fi

    # mysql启动成功后的操作
    source /etc/profile

    echo_info 设置密码
    mysql -uroot -p"${login_pass}" --connect-expired-password -e "SET PASSWORD = PASSWORD('${my_root_passwd}');flush privileges;" &> /dev/null
    
    echo_info 重启mysql
    systemctl restart ${unit_file_name}
    echo_info 设置所有主机均可访问mysql
    mysql -uroot -p"${my_root_passwd}" -e "grant all on *.* to root@'%' identified by '${my_root_passwd}' WITH GRANT OPTION;" &> /dev/null

    echo_info 重启mysql
    systemctl restart ${unit_file_name}

    echo_info mysql已启动成功！相关信息如下：
    echo -e "\033[37m                  端口：${PORT}\033[0m"
    echo -e "\033[37m                  账号：root\033[0m"
    echo -e "\033[37m                  密码：${my_root_passwd}\033[0m"

    echo_info mysql控制命令：
    echo -e "\033[37m                  启动：systemctl start ${unit_file_name}\033[0m"
    echo -e "\033[37m                  重启：systemctl restart ${unit_file_name}\033[0m"
    echo -e "\033[37m                  停止：systemctl stop ${unit_file_name}\033[0m"
}

function pre_install(){
    if [[ $os == 'centos' ]];then
        # 卸载mariadb
        mariadb_pkgs=$(rpm -qa | grep -i mariadb)
        mariadb_pkgs_num=$(echo $mariadb_pkgs | wc -l)
        if [ $mariadb_pkgs_num -ne 0 ];then
            echo_info 卸载之前的mariadb包，请耐心等待...
            for pkg in $mariadb_pkgs
            do
                rpm -e --nodeps $pkg
            done
        fi

        echo_info 安装依赖
        yum install -y perl-Data-Dumper perl-JSON libaio libaio-devel
    elif [[ $os == 'ubuntu' ]];then
        mysql_pkgs_num=$(dpkg -l | grep mysql- | wc -l)
        if [ $mysql_pkgs_num -ne 0 ];then
            echo_info 卸载之前的mysql
            dpkg -l | grep mysql- | awk '{print $2}' | xargs dpkg -P
        fi

        echo_info 安装相关依赖
        apt install -y libtinfo5 libmecab2
    fi
}

function gen_my_cnf() {
    echo_info 配置/etc/my.cnf
    check_dir ${DIR}/${mysql_dir_name}
    # 创建数据目录
    mkdir -p ${DIR}/${mysql_dir_name}/{data,log}
    chown -R mysql:mysql ${DIR}/${mysql_dir_name}

    if [[ $os == 'centos' ]];then
        my_cnf_file=/etc/my.cnf
    elif [[ $os == 'ubuntu' ]];then
        my_cnf_file=/etc/mysql/mysql.conf.d/mysqld.cnf
    fi

    if [ -f $my_cnf_file ];then
        mv $my_cnf_file ${my_cnf_file}_`date +%F`
        echo_warning 检测到配置文件，已备份为${my_cnf_file}_`date +%F`
    fi

    # 生成新的配置文件
    echo_info 初始化${my_cnf_file}
cat > ${my_cnf_file} << EOF
# The MySQL  Server configuration file.
# For advice on how to change settings please see
# http://dev.mysql.com/doc/refman/5.7/en/server-configuration-defaults.html

[client]
socket = ${DIR}/${mysql_dir_name}/data/mysql.sock

[mysql]
default-character-set = utf8mb4
socket = ${DIR}/${mysql_dir_name}/data/mysql.sock

[mysqld]
#skip_grant_tables
# 跳过dns解析，提升连接速度
skip_name_resolve
bind_address = 0.0.0.0
port = ${PORT}
socket = ${DIR}/${mysql_dir_name}/data/mysql.sock
basedir = ${DIR}/${mysql_dir_name}
datadir = ${DIR}/${mysql_dir_name}/data
max_connections = 200
character_set_server = utf8mb4
default_storage_engine = INNODB
max_allowed_packet = 16M
# 不区分大小写
lower_case_table_names = 1
# 可以避免一些问题
sql_mode = 

log_error = ${DIR}/${mysql_dir_name}/log/mysqld.log

### binlog日志设置
binlog_format = ROW
#设置日志路径，注意路经需要mysql用户有权限写,这里可以写绝对路径,也可以直接写mysql-bin(后者默认就是在/var/lib/mysql目录下)
log_bin = ${DIR}/${mysql_dir_name}/data/mysql-bin.log
#设置binlog清理时间
expire_logs_days = 7
#binlog每个日志文件大小
max_binlog_size = 100m
#binlog缓存大小
binlog_cache_size = 4m
#最大binlog缓存大小
max_binlog_cache_size = 512m
#配置serverid
server_id = 1


# 允许符号链接
symbolic_links = 1

EOF

    # rpm或deb安装
    if [[ $software -eq 1 ]];then
        echo 'pid_file=/var/run/mysqld/mysqld.pid' >> ${my_cnf_file}
    fi
}

########## rpm安装mysql
function install_by_rpm(){
    [ -f /var/log/mysqld.log ] && rm -f /var/log/mysqld.log
    download_tar_gz ${src_dir} https://mirrors.aliyun.com/mysql/MySQL-5.7/mysql-${mysql_version}-1.el7.x86_64.rpm-bundle.tar
    cd ${file_in_the_dir}
    untar_tgz mysql-${mysql_version}-1.el7.x86_64.rpm-bundle.tar

    pre_install

    # 删除测试套件，不需要
    rm -f mysql-community-test-*rpm

    echo_info 使用rpm包安装mysql
    rpm -Uvh ./mysql-community-*rpm 
    #yum install -y ./mysql-community-*rpm
    return_code=$?
    if [[ $return_code -eq 0 || $return_code -eq 1 || $return_code -eq 9 ]];then
        echo_info 已成功安装mysql，即将进行一些优化配置
    else
        echo_error 安装出错，请检查！
        exit 82
    fi

    gen_my_cnf

    systemctl start mysqld  # 这里启动是为了生成临时密码
    temp_pass=$(grep 'temporary password' ${DIR}/${mysql_dir_name}/log/mysqld.log | awk '{print $NF}')
    init_account ${temp_pass}
}

function check_dir() {
    if [ -d $1 ];then
        echo_error 目录 $1 已存在，退出
        exit 83
    fi
}

function install_by_tgz(){
    download_tar_gz ${src_dir} https://mirrors.aliyun.com/mysql/MySQL-5.7/${mysql_tgz}
    cd ${file_in_the_dir}
    untar_tgz ${mysql_tgz}

    pre_install

    check_dir ${DIR}/${mysql_dir_name}
    mv mysql-${mysql_version}-linux-glibc2.12-x86_64 ${DIR}/${mysql_dir_name}

    add_user_and_group mysql

    gen_my_cnf
    echo_info 初始化mysql
    # 初始化
    cd ${DIR}/${mysql_dir_name}
    bin/mysqld --initialize --basedir=${DIR}/${mysql_dir_name} --datadir=${DIR}/${mysql_dir_name}/data  --pid-file=${DIR}/${mysql_dir_name}/data/mysql.pid >/tmp/mysql_password.txt 2>&1

    # 获取初始密码
    init_password=$(awk '/password/ {print $11}' /tmp/mysql_password.txt)
    rm -f /tmp/mysql_password.txt

    # 初始化完成后，data目录会生成文件，所以重新赋权
    chown -R mysql:mysql ${DIR}/${mysql_dir_name}/
    echo_info 初始化完毕

    # 设置systemctl控制
    echo_info 生成${unit_file_name}文件用于systemd控制

cat > /lib/systemd/system/${unit_file_name} << EOF
[Unit]
Description=mysql
After=network.target
[Service]
Type=forking
ExecStart=${DIR}/${mysql_dir_name}/support-files/mysql.server start
ExecStop=${DIR}/${mysql_dir_name}/support-files/mysql.server stop
ExecRestart=${DIR}/${mysql_dir_name}/support-files/mysql.server restart
ExecReload=${DIR}/${mysql_dir_name}/support-files/mysql.server reload
PrivateTmp=true
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    # 添加环境变量，这样就能在任意地方使用mysql全套命令
    echo_info 配置PATH环境变量
    if [ -f /usr/local/bin/mysql ];then
        echo_error /usr/local/bin目录有未删除的mysql相关文件，请检查！
        exit 84
    fi
    if [ -f /usr/bin/mysql ];then
        echo_error /usr/bin目录有未删除的mysql相关文件，请检查！
        exit 85
    fi
    echo "export PATH=\${PATH}:${DIR}/${mysql_dir_name}/bin" > /etc/profile.d/mysql.sh
    source /etc/profile

    # 进行账号、密码设置
    init_account ${init_password}

    echo_warning 由于bash特性限制，在本终端连接mysql需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端连接mysql
}

function is_run_mysql() {
    ps -ef | grep "${DIR}/${mysql_dir_name}" | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到mysql正在运行中，退出
        exit 86
    fi

    if [ -d ${DIR}/${mysql_dir_name} ];then
        echo_error 检测到目录${DIR}/${mysql_dir_name}，请检查是否重复安装，退出
        exit 87
    fi
}

function install_by_deb() {
    download_tar_gz ${src_dir} https://mirrors.aliyun.com/mysql/MySQL-5.7/mysql-server_${mysql_version}-1ubuntu18.04_amd64.deb-bundle.tar
    cd ${file_in_the_dir}
    ls
    untar_tgz mysql-server_${mysql_version}-1ubuntu18.04_amd64.deb-bundle.tar
    # 删除测试套件，不需要
    rm -f mysql-*test*deb

    pre_install

    echo_info 使用deb包安装mysql
    dpkg -i mysql-*.deb
    return_code=$?
    if [[ $return_code -eq 0 || $return_code -eq 1 ]];then
        echo_info 已成功安装mysql，即将进行一些优化配置
    else
        echo_error 安装出错，请检查！
        exit 88
    fi

    # ubuntu安装完mysql会启动，这里先停掉
    systemctl stop mysql

    gen_my_cnf
    echo_info 迁移mysql数据目录
    rm -rf ${DIR}/${mysql_dir_name}/data
    mv /var/lib/mysql ${DIR}/${mysql_dir_name}/data
    chown -R mysql:mysql ${DIR}/${mysql_dir_name}/data

    echo_info 禁用apparmor
    if [ -e /etc/apparmor.d/usr.sbin.mysqld ];then
        rm -f /etc/apparmor.d/disable/usr.sbin.mysqld
        ln -s /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/disable/
        apparmor_parser -R /etc/apparmor.d/usr.sbin.mysqld
    fi

    echo_info 启动mysql
    systemctl start ${unit_file_name}

    echo_info 设置所有主机均可访问mysql
    read -p "请输入刚才设置的root密码：" my_root_passwd
    mysql -uroot -p"${my_root_passwd}" -e "grant all on *.* to root@'%' identified by '${my_root_passwd}' WITH GRANT OPTION;" &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 设置权限失败，请确认输入的密码是否正确
        exit 96
    fi

    echo_info 重启mysql
    systemctl restart ${unit_file_name}

    echo_info mysql已启动成功！相关信息如下：
    echo -e "\033[37m                  端口：${PORT}\033[0m"
    echo -e "\033[37m                  账号：root\033[0m"
    echo -e "\033[37m                  密码：${my_root_passwd}\033[0m"

    echo_info mysql控制命令：
    echo -e "\033[37m                  启动：systemctl start ${unit_file_name}\033[0m"
    echo -e "\033[37m                  重启：systemctl restart ${unit_file_name}\033[0m"
    echo -e "\033[37m                  停止：systemctl stop ${unit_file_name}\033[0m"
}


function install_main_func(){
    read -p "请输入数字选择安装类型（如需退出请输入q）：" software
    if [[ $os == 'centos' ]];then
        case $software in
            1)
                echo_info 即将使用 rpm包 安装mysql
                # 等待1秒，给用户手动取消的时间
                sleep 1
                install_by_rpm
                ;;
            2)
                echo_info 即将使用 二进制包 安装mysql
                sleep 1
                install_by_tgz
                ;;
            q|Q)
                exit 0
                ;;
            *)
                install_main_func
                ;;
        esac
    elif [[ $os == 'ubuntu' ]];then
        case $software in
            1)
                echo_info 即将使用 deb包 安装mysql
                # 等待1秒，给用户手动取消的时间
                sleep 1
                install_by_deb
                ;;
            2)
                echo_info 即将使用 二进制包 安装mysql
                sleep 1
                install_by_tgz_ubuntu
                ;;
            q|Q)
                exit 0
                ;;
            *)
                install_main_func
                ;;
        esac
    fi
}

is_run_mysql

if [[ $os == 'centos' ]];then
    echo -e "\033[31m本脚本支持两种部署方式：\033[0m"
    echo -e "\033[36m[1]\033[32m rpm包部署mysql\033[0m"
    echo -e "\033[36m[2]\033[32m 二进制包部署mysql\033[0m"
elif [[ $os == 'ubuntu' ]];then
    echo -e "\033[31m本脚本支持两种部署方式：\033[0m"
    echo -e "\033[36m[1]\033[32m deb包部署mysql\033[0m"
    echo -e "\033[36m[2]\033[32m 二进制包部署mysql\033[0m"
fi
install_main_func