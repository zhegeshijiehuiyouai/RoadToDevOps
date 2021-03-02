#!/bin/bash

# 脚本功能：自动部署mysql5.7
# 测试系统：CentOS7.6
# mysql安装文件：二进制包
#
# mysql下载地址：https://cdn.mysql.com/Downloads/MySQL-5.7/mysql-5.7.33-linux-glibc2.12-x86_64.tar.gz
# 或者官网下载
#
# 将本脚本和二进制包放在同一目录下，脚本会在本目录下创建mysql作为mysql安装目录
#
# 本脚本默认会下载二进制包，如果自己上传，可以注释掉
# 2020.11.10新增rpm包部署选项

#######################定义变量##############################
# 包下载目录
src_dir=$(pwd)/00src00
# 端口
PORT=3306
# mysql部署好后，root的默认密码
my_root_passwd=123456
# mysql版本
mysql_version=5.7.33

#****************以上为通用变量*****************************
#****************以下为二进制部署才需要的变量******************
# 部署目录的父目录
DIR=$(pwd)
# 部署目录的名字，最终的部署目录为${DIR}/${mysql_dir_name}
mysql_dir_name=mysql-${mysql_version}

# 解压后的名字
FILE=mysql-${mysql_version}-linux-glibc2.12-x86_64
# mysql二进制包名字
mysql_tgz=${FILE}.tar.gz
#############################################################

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
    systemd_service_name=$2

    systemctl enable ${systemd_service_name}.service >/dev/null 2>&1
    systemctl start ${systemd_service_name}.service
    # mysql启动失败的话退出
    if [ $? -ne 0 ];then
        echo_error mysql启动失败，请查看错误信息
        exit 2
    fi

    # mysql启动成功后的操作
    source /etc/profile

    echo_info 设置密码
    if [ ${systemd_service_name} == mysqld ];then
        mysql -uroot -p"${login_pass}" --connect-expired-password -e "set global validate_password_policy=0;set global validate_password_mixed_case_count=0;set global validate_password_number_count=3;set global validate_password_special_char_count=0;set global validate_password_length=3;" &> /dev/null
    fi
    mysql -uroot -p"${login_pass}" --connect-expired-password -e "SET PASSWORD = PASSWORD('${my_root_passwd}');flush privileges;" &> /dev/null
    echo_info 重启mysql
    systemctl restart ${systemd_service_name}
    echo_info 设置所有主机均可访问mysql
    if [ ${systemd_service_name} == mysqld ];then
        mysql -uroot -p"${my_root_passwd}" -e "set global validate_password_policy=0;set global validate_password_mixed_case_count=0;set global validate_password_number_count=3;set global validate_password_special_char_count=0;set global validate_password_length=3;grant all on *.* to root@'%' identified by '${my_root_passwd}' WITH GRANT OPTION;" &> /dev/null
    else
        mysql -uroot -p"${my_root_passwd}" -e "grant all on *.* to root@'%' identified by '${my_root_passwd}' WITH GRANT OPTION;" &> /dev/null
    fi
    echo_info 重启mysql
    systemctl restart ${systemd_service_name}

    echo_info mysql已启动成功！相关信息如下：
    echo -e "\033[37m                  端口号：${PORT}\033[0m"
    echo -e "\033[37m                  账号：root\033[0m"
    echo -e "\033[37m                  密码：${my_root_passwd}\033[0m"

    echo_info mysql控制命令：
    echo -e "\033[37m                  启动：systemctl start ${systemd_service_name}\033[0m"
    echo -e "\033[37m                  重启：systemctl restart ${systemd_service_name}\033[0m"
    echo -e "\033[37m                  停止：systemctl stop ${systemd_service_name}\033[0m"
}

########## rpm安装mysql
function install_by_rpm(){
    [ -f /var/log/mysqld.log ] && :>/var/log/mysqld.log
    download_tar_gz ${src_dir} http://mirrors.163.com/mysql/Downloads/MySQL-5.7/mysql-${mysql_version}-1.el7.x86_64.rpm-bundle.tar
    cd ${file_in_the_dir}
    untar_tgz mysql-${mysql_version}-1.el7.x86_64.rpm-bundle.tar
    echo_info 使用rpm包安装mysql
    rpm -Uvh ./mysql-community-*rpm 
    #yum install -y ./mysql-community-*rpm 
    if [ $? -eq 0 ];then
        echo_info 已成功安装mysql，即将进行一些优化配置
    else
        echo_error 安装出错，请检查！
        exit 3
    fi

    if [ -f /etc/my.cnf ];then
        mv /etc/my.cnf /etc/my.cnf_`date +%F`
        echo_warning 检测到配置文件，已备份为/etc/my.cnf_`date +%F`
    fi

    # 生成新的/etc/my.cnf
    echo_info 初始化/etc/my.cnf
cat > /etc/my.cnf << EOF
# For advice on how to change settings please see
# http://dev.mysql.com/doc/refman/5.7/en/server-configuration-defaults.html
[client]
socket=/var/lib/mysql/mysql.sock

[mysql]
default-character-set=utf8
socket=/var/lib/mysql/mysql.sock

[mysqld]
#skip-grant-tables
# 跳过dns解析，提升连接速度
skip-name-resolve
port=${PORT}
socket=${DIR}/${mysql_dir_name}/data/mysql.sock
basedir=${DIR}/${mysql_dir_name}
datadir=${DIR}/${mysql_dir_name}/data
max_connections=200
character-set-server=utf8
default-storage-engine=INNODB
max_allowed_packet=16M
# 不区分大小写
lower_case_table_names = 1

datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock
log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
EOF

    systemctl start mysqld  # 这里启动是为了生成临时密码
    temp_pass=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
    init_account ${temp_pass} mysqld
}

function check_dir() {
    if [ -d $1 ];then
        echo_error 目录 $1 已存在，退出
        exit 4
    fi
}

function install_by_tgz(){
    download_tar_gz ${src_dir} http://mirrors.163.com/mysql/Downloads/MySQL-5.7/${mysql_tgz}
    #download_tar_gz ${src_dir} https://mirrors.cloud.tencent.com/mysql/downloads/MySQL-5.7/${mysql_tgz}
    cd ${file_in_the_dir}
    untar_tgz ${mysql_tgz}

    check_dir ${DIR}/${mysql_dir_name}
    mv ${FILE} ${DIR}/${mysql_dir_name}

    add_user_and_group mysql

    echo_info 初始化mysql
    mkdir -p ${DIR}/${mysql_dir_name}/data
    chown -R mysql:mysql ${DIR}/${mysql_dir_name}/

    # 初始化
    cd ${DIR}/${mysql_dir_name}
    bin/mysqld --initialize --basedir=${DIR}/${mysql_dir_name} --datadir=${DIR}/${mysql_dir_name}/data  --pid-file=${DIR}/${mysql_dir_name}/data/mysql.pid >/tmp/mysql_password.txt 2>&1

    # 获取初始密码
    init_password=$(awk '/password/ {print $11}' /tmp/mysql_password.txt)
    rm -f /tmp/mysql_password.txt

    # 初始化完成后，data目录会生成文件，所以重新赋权
    chown -R mysql:mysql ${DIR}/${mysql_dir_name}/
    echo_info 初始化完毕

    # 备份原来的/etc/my.cnf
    if [ -f /etc/my.cnf ];then
        mv /etc/my.cnf /etc/my.cnf_`date +%F`
        echo_warning 检测到配置文件，已备份为/etc/my.cnf_`date +%F`
    fi

    # 生成新的/etc/my.cnf
    echo_info 初始化/etc/my.cnf
cat > /etc/my.cnf << EOF
[client]
socket=${DIR}/${mysql_dir_name}/data/mysql.sock

[mysql]
default-character-set=utf8
socket=${DIR}/${mysql_dir_name}/data/mysql.sock

[mysqld]
#skip-grant-tables
skip-name-resolve
port=${PORT}
socket=${DIR}/${mysql_dir_name}/data/mysql.sock
basedir=${DIR}/${mysql_dir_name}
datadir=${DIR}/${mysql_dir_name}/data
max_connections=200
character-set-server=utf8
default-storage-engine=INNODB
max_allowed_packet=16M
# 不区分大小写
lower_case_table_names = 1
EOF

    # 设置systemctl控制
    echo_info 生成mysql.service文件用于systemd控制

cat > /lib/systemd/system/mysql.service << EOF
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
        exit 5
    fi
    if [ -f /usr/bin/mysql ];then
        echo_error /usr/bin目录有未删除的mysql相关文件，请检查！
        exit 6
    fi
    echo "export PATH=\${PATH}:${DIR}/${mysql_dir_name}/bin" > /etc/profile.d/mysql.sh
    source /etc/profile

    # 进行账号、密码设置
    init_account ${init_password} mysql

    echo_warning 由于bash特性限制，在本终端连接mysql需要先手动执行 source /etc/profile 加载环境变量，或者新开一个终端连接mysql
}

function is_run_mysql() {
    ps -ef | grep "${DIR}/${mysql_dir_name}" | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到mysql正在运行中，退出
        exit 7
    fi

    if [ -d ${DIR}/${mysql_dir_name} ];then
        echo_error 检测到目录${DIR}/${mysql_dir_name}，请检查是否重复安装，退出
        exit 8
    fi
}

function install_main_func(){
    read -p "请输入数字选择安装类型（如需退出请输入q）：" software
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
}

is_run_mysql

echo -e "\033[31m本脚本支持两种部署方式：\033[0m"
echo -e "\033[36m[1]\033[32m rpm包部署mysql\033[0m"
echo -e "\033[36m[2]\033[32m 二进制包部署mysql\033[0m"
install_main_func