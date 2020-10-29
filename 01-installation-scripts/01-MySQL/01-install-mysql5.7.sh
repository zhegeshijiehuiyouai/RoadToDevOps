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

#######################定义变量##############################
# 部署目录的父目录
DIR=$(pwd)
# 部署目录的名字，最终的部署目录为${DIR}/${mysql_dir_name}
mysql_dir_name=mysql
# 源码下载目录
src_dir=$(pwd)/00src00
# 端口
PORT=3306
# mysql部署好后，root的默认密码
my_root_passwd=123456
# mysql版本
mysql_version=5.7.32

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
#   II.如果没有压缩包，那么就检查有没有 ${openssh_source_dir} 表示的目录;
#       1) 如果有目录，那么检查有没有压缩包
#           ① 有压缩包就解压
#           ② 没有压缩包则下载压缩包
#       2) 如果没有,那么就创建这个目录，然后 cd 到目录中，然后下载压缩包，然
#       后解压
# 解压的步骤都在后面，故此处只做下载

# 语法： download_tar_gz 文件名 保存的目录 下载链接
# 使用示例： download_tar_gz openssl-1.1.1h.tar.gz /data/openssh-update https://mirrors.cloud.tencent.com/openssl/source/openssl-1.1.1h.tar.gz
function download_tar_gz(){
    back_dir=$(pwd)
    file_in_the_dir=''  # 这个目录是后面编译目录的父目录

    ls $1 &> /dev/null
    if [ $? -ne 0 ];then
        # 进入此处表示脚本所在目录没有压缩包
        ls -d $2 &> /dev/null
        if [ $? -ne 0 ];then
            # 进入此处表示没有${openssh_source_dir}目录
            mkdir -p $2 && cd $2
            echo -e "\033[32m[+] 下载源码包 $1 至 $(pwd)/\033[0m"
            wget $3
            file_in_the_dir=$(pwd)
            # 返回脚本所在目录，这样这个函数才可以多次使用
            cd ${back_dir}
        else
            # 进入此处表示有${openssh_source_dir}目录
            cd $2
            ls $1 &> /dev/null
            if [ $? -ne 0 ];then
            # 进入此处表示${openssh_source_dir}目录内没有压缩包
                echo -e "\033[32m[+] 下载源码包 $1 至 $(pwd)/\033[0m"
                wget $3
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            else
                # 进入此处，表示${openssh_source_dir}目录内有压缩包
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

systemctl enable mysql.service >/dev/null 2>&1
systemctl start mysql.service
# mysql启动失败的话退出
if [ $? -ne 0 ];then
    echo -e "\n\033[31m[*] mysql启动失败，请查看错误信息\033[0m\n"
    exit 1
else

# mysql启动成功后的操作
source /etc/profile

echo -e "\033[36m[+] 设置密码\033[0m"
mysql -uroot -p"${init_password}" --connect-expired-password -e "SET PASSWORD = PASSWORD('${my_root_passwd}');flush privileges;" &> /dev/null
echo -e "\033[36m[+] 重启mysql\033[0m"
systemctl restart mysql
echo -e "\033[36m[+] 设置所有主机均可访问mysql\033[0m"
mysql -uroot -p"${my_root_passwd}" -e "grant all on *.* to root@'%' identified by '${my_root_passwd}'" &> /dev/null
echo -e "\033[36m[+] 重启mysql\033[0m"
systemctl restart mysql

    echo -e "\nmysql已启动成功!相关信息如下："
    echo -e "    端口号：\033[32m${PORT}\033[0m"
    echo -e "    账号：\033[32mroot\033[0m"
    echo -e "    密码：\033[32m${my_root_passwd}\033[0m"

    echo -e "\nmysql控制命令："
    echo -e "    启动：\033[32msystemctl start mysql\033[0m"
    echo -e "    重启：\033[32msystemctl restart mysql\033[0m"
    echo -e "    停止：\033[32msystemctl stop mysql\n\033[0m"
fi

echo -e "\033[32m由于bash特性限制，在本终端连接mysql需要先手动执行  \033[36msource /etc/profile\033[0m  \033[32m加载环境变量\033[0m"
echo -e "\033[33m或者\033[32m新开一个终端连接mysql\n\033[0m"