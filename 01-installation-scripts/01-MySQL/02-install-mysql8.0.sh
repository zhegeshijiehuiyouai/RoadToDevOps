#!/bin/bash

# 脚本功能：自动部署mysql8.0
# 测试系统：CentOS7.6
# mysql安装文件：二进制包
#
# 将本脚本和二进制包放在同一目录下，脚本会在本目录下创建mysql作为mysql安装目录
#
# 本脚本默认会下载二进制包，如果自己上传，可以注释掉

#######################定义变量##############################
# 部署目录的父目录
DIR=$(pwd)
# 部署目录的名字，最终的部署目录为${DIR}/${mysql_dir_name}
mysql_dir_name=mysql-8
# 源码下载目录
src_dir=$(pwd)/00src00
# 端口
PORT=3306
# mysql部署好后，root的默认密码
my_root_passwd=123456
# mysql版本
mysql8_version=8.0.17

# 解压后的名字
FILE=mysql-${mysql8_version}-el7-x86_64
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
#   II.如果没有压缩包，那么就检查有没有 ${openssh_source_dir} 表示的目录;
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

    # 检测下载文件是否在服务器上存在
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
            echo -e "\033[32m[+] 下载 $download_file_name 至 $(pwd)/\033[0m"
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
                echo -e "\033[32m[+] 下载 $download_file_name 至 $(pwd)/\033[0m"
                wget $2
                if [ $? -ne 0 ];then
                    echo_error 下载 $2 失败！
                    exit 1
                fi
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


download_tar_gz ${src_dir} http://mirrors.sohu.com/mysql/MySQL-8.0/${mysql_tgz}
cd ${file_in_the_dir}
untar_tgz ${mysql_tgz}


mv ${FILE} ${DIR}/${mysql_dir_name}

add_user_and_group mysql


echo "初始化mysql..."

mkdir -p ${DIR}/${mysql_dir_name}/data
chown -R mysql:mysql ${DIR}/${mysql_dir_name}/

# 初始化
cd ${DIR}/${mysql_dir_name}
bin/mysqld --initialize --basedir=${DIR}/${mysql_dir_name} --datadir=${DIR}/${mysql_dir_name}/data  --pid-file=${DIR}/${mysql_dir_name}/data/mysql.pid >/dev/null 2>&1
echo "初始化完毕"
# 初始化完成后，data目录会生成文件，所以重新赋权
chown -R mysql:mysql ${DIR}/${mysql_dir_name}/
echo "mysql目录授权成功"

# 如果原来有my.cnf，则备份原来的/etc/my.cnf
if [ -f /etc/my.cnf ];then
    mv /etc/my.cnf /etc/my.cnf_`date +%F`
    echo -e "\033[31m备份/etc/my.cnf_`date +%F`\033[0m"
fi

# 生成新的/etc/my.cnf
echo "初始化/etc/my.cnf..."
cat > /etc/my.cnf << EOF
[client]
socket=${DIR}/${mysql_dir_name}/data/mysql.sock

[mysql]
default_character_set=utf8mb4
socket=${DIR}/${mysql_dir_name}/data/mysql.sock

[mysqld]
skip_grant_tables
skip_name_resolve
port=${PORT}
socket=${DIR}/${mysql_dir_name}/data/mysql.sock
basedir=${DIR}/${mysql_dir_name}
datadir=${DIR}/${mysql_dir_name}/data
max_connections=200
character_set_server=utf8mb4
default_storage_engine=INNODB
max_allowed_packet=16M
lower_case_table_names = 1
EOF
echo "/etc/my.cnf初始化完毕"


# 设置systemctl控制
if [ -f /lib/systemd/system/mysql.service ];then
    mv /lib/systemd/system/mysql.service /lib/systemd/system/mysql.service_`date +%F`
    echo -e "\033[31m备份/lib/systemd/system/mysql.service_`date +%F`\033[0m"
fi
echo "设置systemctl启动文件，之后使用systemctl start mysql启动"

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
echo "export PATH=\${PATH}:${DIR}/${mysql_dir_name}/bin" > /etc/profile.d/mysql.sh
source /etc/profile
if [ -f /usr/local/bin/mysql ];then
    echo "/usr/local/bin目录有未删除的mysql相关文件，请检查！"
fi
if [ -f /usr/bin/mysql ];then
    echo "/usr/bin目录有未删除的mysql相关文件，请检查！"
fi

echo "设置完毕"
systemctl enable mysql.service >/dev/null 2>&1
systemctl start mysql.service
# mysql启动失败的话退出
if [ $? -ne 0 ];then
    echo -e "\n\033[31mmysql启动失败，请查看错误信息\033[0m\n"
    exit 1
else
# 提供一些提示信息	
    echo -e "mysql已启动成功，端口号为：\033[32m${PORT}\033[0m\n"
    cat << EOF
mysql控制命令：
    启动：systemctl start mysql
    重启：systemctl restart mysql
    停止：systemctl stop mysql
EOF
    echo -e "\033[36m请先执行 \033[0m\033[33msource /etc/profile\033[0m\033[36m 加载环境变量，或者新开一个终端执行下面的命令\033[0m"
    echo -e "\n请输入命令：\033[33mmysql\033[0m，进入MySQL修改密码"
    echo -e "首先将密码置空："
    echo -e "\033[32mmysql> use mysql;\033[0m"
    echo -e "\033[32mmysql> update user set authentication_string = '' where user = 'root';\033[0m"
    echo -e "\033[32mmysql> flush privileges;\033[0m"
    echo -e "请务必在修改密码后将/etc/my.cnf的skip_grant_tables注释掉并重启mysql"
    echo "然后修改密码，不修改将无法操作"
    echo -e "\033[32mmysql> ALTER USER 'root'@'localhost' IDENTIFIED BY '123456' PASSWORD EXPIRE NEVER; \033[0m"
    echo -e "\033[32mmysql> flush privileges;\033[0m"
    echo -e "\n再次重启mysql"
    echo -e "\033[34m"
    cat << EOF
mysql8.0后不能使用grant创建用户了，并且设置密码时需要指定 GRANT OPTION，所以远程登录请这么设置
mysql> CREATE USER 'root'@'%' IDENTIFIED BY 'root';
mysql> ALTER USER 'root'@'%' IDENTIFIED WITH mysql_native_password BY '123456';

EOF
    echo -e "\033[0m"
fi