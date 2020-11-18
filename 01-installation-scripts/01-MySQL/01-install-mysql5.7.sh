#!/bin/bash

# 脚本功能：自动部署mysql5.7
# 测试系统：CentOS7.6
# mysql安装文件：二进制包
#
# mysql下载地址：https://cdn.mysql.com/Downloads/MySQL-5.7/mysql-5.7.32-linux-glibc2.12-x86_64.tar.gz
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
mysql_version=5.7.32

#****************以上为通用变量*****************************
#****************以下为二进制部署才需要的变量******************
# 部署目录的父目录
DIR=$(pwd)
# 部署目录的名字，最终的部署目录为${DIR}/${mysql_dir_name}
mysql_dir_name=mysql

# 解压后的名字
FILE=mysql-${mysql_version}-linux-glibc2.12-x86_64
# mysql二进制包名字
mysql_tgz=${FILE}.tar.gz
#############################################################

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

# 语法： download_tar_gz 文件名 保存的目录 下载链接
# 使用示例： download_tar_gz openssl-1.1.1h.tar.gz /data/openssh-update https://mirrors.cloud.tencent.com/openssl/source/openssl-1.1.1h.tar.gz
function download_tar_gz(){
    # 检测是否有wget工具
    if [ ! -f /usr/bin/wget ];then
        echo -e "\033[32m[+] 安装wget工具\033[0m"
        yum install -y wget
    fi

    back_dir=$(pwd)
    file_in_the_dir=''  # 这个目录是后面编译目录的父目录

    ls $1 &> /dev/null
    if [ $? -ne 0 ];then
        # 进入此处表示脚本所在目录没有压缩包
        ls -d $2 &> /dev/null
        if [ $? -ne 0 ];then
            # 进入此处表示没有${src_dir}目录
            mkdir -p $2 && cd $2
            echo -e "\033[32m[+] 下载 $1 至 $(pwd)/\033[0m"
            wget $3
            file_in_the_dir=$(pwd)
            # 返回脚本所在目录，这样这个函数才可以多次使用
            cd ${back_dir}
        else
            # 进入此处表示有${src_dir}目录
            cd $2
            ls $1 &> /dev/null
            if [ $? -ne 0 ];then
            # 进入此处表示${src_dir}目录内没有压缩包
                echo -e "\033[32m[+] 下载 $1 至 $(pwd)/\033[0m"
                wget $3
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            else
                # 进入此处，表示${src_dir}目录内有压缩包
                echo -e "\033[32m[!] 发现压缩包$(pwd)/$1\033[0m"
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            fi
        fi
    else
        # 进入此处表示脚本所在目录有压缩包
        echo -e "\033[32m[!] 发现压缩包$(pwd)/$1\033[0m"
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

function init_account(){
    login_pass=$1
    systemd_service_name=$2

    systemctl enable ${systemd_service_name}.service >/dev/null 2>&1
    systemctl start ${systemd_service_name}.service
    # mysql启动失败的话退出
    if [ $? -ne 0 ];then
        echo -e "\n\033[31m[*] mysql启动失败，请查看错误信息\033[0m\n"
        exit 1
    fi

    # mysql启动成功后的操作
    source /etc/profile

    echo -e "\033[36m[+] 设置密码\033[0m"
    if [ ${systemd_service_name} == mysqld ];then
        mysql -uroot -p"${login_pass}" --connect-expired-password -e "set global validate_password_policy=0;set global validate_password_mixed_case_count=0;set global validate_password_number_count=3;set global validate_password_special_char_count=0;set global validate_password_length=3;" &> /dev/null
    fi
    mysql -uroot -p"${login_pass}" --connect-expired-password -e "SET PASSWORD = PASSWORD('${my_root_passwd}');flush privileges;" &> /dev/null
    echo -e "\033[36m[+] 重启mysql\033[0m"
    systemctl restart ${systemd_service_name}
    echo -e "\033[36m[+] 设置所有主机均可访问mysql\033[0m"
    if [ ${systemd_service_name} == mysqld ];then
        mysql -uroot -p"${my_root_passwd}" -e "set global validate_password_policy=0;set global validate_password_mixed_case_count=0;set global validate_password_number_count=3;set global validate_password_special_char_count=0;set global validate_password_length=3;grant all on *.* to root@'%' identified by '${my_root_passwd}'" &> /dev/null
    else
        mysql -uroot -p"${my_root_passwd}" -e "grant all on *.* to root@'%' identified by '${my_root_passwd}'" &> /dev/null
    fi
    echo -e "\033[36m[+] 重启mysql\033[0m"
    systemctl restart ${systemd_service_name}
    
    echo -e "\nmysql已启动成功!相关信息如下："
    echo -e "    端口号：\033[32m${PORT}\033[0m"
    echo -e "    账号：\033[32mroot\033[0m"
    echo -e "    密码：\033[32m${my_root_passwd}\033[0m"

    echo -e "\nmysql控制命令："
    echo -e "    启动：\033[32msystemctl start ${systemd_service_name}\033[0m"
    echo -e "    重启：\033[32msystemctl restart ${systemd_service_name}\033[0m"
    echo -e "    停止：\033[32msystemctl stop ${systemd_service_name}\n\033[0m"
}

########## rpm安装mysql
function install_by_rpm(){
    download_tar_gz mysql-${mysql_version}-1.el7.x86_64.rpm-bundle.tar ${src_dir} https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-${mysql_version}-1.el7.x86_64.rpm-bundle.tar
    cd ${file_in_the_dir}
    untar_tgz mysql-${mysql_version}-1.el7.x86_64.rpm-bundle.tar
    echo -e "\033[32m[>] 使用rpm包安装mysql\033[0m"
    yum install -y ./mysql-community-*rpm 
    if [ $? -eq 0 ];then
        echo -e "\033[32m[+] 已成功安装mysql，即将进行一些优化配置\033[0m"
    else
        echo -e "\033[31m[*] 安装出错，请检查!\033[0m"
        exit 5
    fi

    # 备份原来的/etc/my.cnf
    if [ -f /etc/my.cnf ];then
        mv /etc/my.cnf /etc/my.cnf_`date +%F`
        echo -e "\033[36m[*] 备份/etc/my.cnf_`date +%F`\033[0m"
    fi

    # 生成新的/etc/my.cnf
    echo -e "\033[32m[+] 初始化/etc/my.cnf\033[0m"
cat > /etc/my.cnf << EOF
# For advice on how to change settings please see
# http://dev.mysql.com/doc/refman/5.7/en/server-configuration-defaults.html
[client]
socket=/var/lib/mysql/mysql.sock

[mysql]
default-character-set=utf8
socket=/var/lib/mysql/mysql.sock

[mysqld]
#
# Remove leading # and set to the amount of RAM for the most important data
# cache in MySQL. Start at 70% of total RAM for dedicated server, else 10%.
# innodb_buffer_pool_size = 128M
#
# Remove leading # to turn on a very important data integrity option: logging
# changes to the binary log between backups.
# log_bin
#
# Remove leading # to set options mainly useful for reporting servers.
# The server defaults are faster for transactions and fast SELECTs.
# Adjust sizes as needed, experiment to find the optimal values.
# join_buffer_size = 128M
# sort_buffer_size = 2M
# read_rnd_buffer_size = 2M
port=${PORT}
max_connections=200
character-set-server=utf8
default-storage-engine=INNODB
max_allowed_packet=16M
lower_case_table_names = 1

datadir=/var/lib/mysql
socket=/var/lib/mysql/mysql.sock

# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links=0

log-error=/var/log/mysqld.log
pid-file=/var/run/mysqld/mysqld.pid
EOF

    systemctl start mysqld  # 这里启动是为了生成临时密码
    temp_pass=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
    init_account ${temp_pass} mysqld
}

function install_by_tgz(){
    download_tar_gz ${mysql_tgz} ${src_dir} https://cdn.mysql.com/Downloads/MySQL-5.7/${mysql_tgz}
    cd ${file_in_the_dir}
    untar_tgz ${mysql_tgz}


    mv ${FILE} ${DIR}/${mysql_dir_name}

    add_user_and_group mysql

    echo -e "\033[32m[+] 初始化mysql\033[0m"

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
    echo -e "\033[32m[+] 初始化完毕\033[0m"

    # 备份原来的/etc/my.cnf
    if [ -f /etc/my.cnf ];then
        mv /etc/my.cnf /etc/my.cnf_`date +%F`
        echo -e "\033[36m[*] 备份/etc/my.cnf_`date +%F`\033[0m"
    fi

    # 生成新的/etc/my.cnf
    echo -e "\033[32m[+] 初始化/etc/my.cnf\033[0m"
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
lower_case_table_names = 1
EOF

    # 设置systemctl控制
    echo -e "\033[32m[+] 设置systemctl启动文件\033[0m"

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
[Install]
WantedBy=multi-user.target
EOF

    # 添加环境变量，这样就能在任意地方使用mysql全套命令
    echo -e "\033[32m[+] 配置PATH环境变量\033[0m"
    if [ -f /usr/local/bin/mysql ];then
        echo -e "\033[31m[*] /usr/local/bin目录有未删除的mysql相关文件，请检查！\033[0m"
        exit 10
    fi
    if [ -f /usr/bin/mysql ];then
        echo  -e"\033[31m[*] /usr/bin目录有未删除的mysql相关文件，请检查！\033[0m"
        exit 10
    fi
    echo "export PATH=${PATH}:${DIR}/${mysql_dir_name}/bin" > /etc/profile.d/mysql.sh
    source /etc/profile

    # 进行账号、密码设置
    init_account ${init_password} mysql

    echo -e "\033[32m由于bash特性限制，在本终端连接mysql需要先手动执行  \033[36msource /etc/profile\033[0m  \033[32m加载环境变量\033[0m"
    echo -e "\033[33m或者\033[32m新开一个终端连接mysql\n\033[0m"
}

function install_main_func(){
    read -p "请输入数字选择安装类型（如需退出请输入q）：" software
    case $software in
        1)
            echo -e "\033[32m[!] 即将使用 \033[36mrpm包\033[32m 安装mysql\033[0m"
            # 等待两秒，给用户手动取消的时间
            sleep 2
            install_by_rpm
            ;;
        2)
            echo -e "\033[32m[!] 即将使用 \033[36m二进制包\033[32m 安装mysql\033[0m"
            sleep 2
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

echo -e "\033[31m\n\033[0m"
echo -e "\033[36m[1]\033[32m rpm包部署mysql"
echo -e "\033[36m[2]\033[32m 二进制包部署mysql"
# 终止终端字体颜色
echo -e "\033[0m"
install_main_func