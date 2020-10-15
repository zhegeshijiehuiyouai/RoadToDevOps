#!/bin/bash

# 脚本功能：自动部署mysql8.0
# 测试系统：CentOS7.6
# mysql安装文件：二进制包
#
# 将本脚本和二进制包放在同一目录下，脚本会在本目录下创建mysql作为mysql安装目录
#
# 本脚本默认会下载二进制包，如果自己上传，可以注释掉

# 部署目录
DIR=`pwd`
# 端口
PORT=3306
# 解压后的名字
FILE=mysql-8.0.17-el7-x86_64
# mysql二进制包名字
Archive=${FILE}.tar.gz

# 判断是否存在压缩包，没有的话就下载网易镜像站的mysql压缩包
ls ${Archive} &> /dev/null
[ $? -eq 0 ] || wget http://mirrors.sohu.com/mysql/MySQL-8.0/${Archive}

# 解压
echo "解压中，请稍候..."
tar -zxf ${Archive} >/dev/null 2>&1
if [ $? -eq 0 ];then
    echo "解压完毕"
else
    echo "解压出错，请检查"
    exit 2
fi

# 更改文件名
mysql_dir_name=mysql-8
mv ${FILE} ${mysql_dir_name}

#创建mysql用户
if id -g mysql >/dev/null 2>&1; then
    echo "mysql组已存在，无需创建"
else
    groupadd mysql
    echo "+++创建mysql组"
fi
if id -u mysql >/dev/null 2>&1; then
    echo "mysql用户已存在，无需创建"
else
    useradd -M -g mysql -s /sbin/nologin mysql
    echo "+++创建mysql用户"
fi


echo "初始化mysql..."

mkdir -p ${DIR}/${mysql_dir_name}/data
chown -R mysql:mysql ${DIR}/${mysql_dir_name}/

# 初始化
cd ${mysql_dir_name}
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
default-character-set=utf8
socket=${DIR}/${mysql_dir_name}/data/mysql.sock

[mysqld]
skip-grant-tables
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
[Install]
WantedBy=multi-user.target
EOF

# 添加环境变量，这样就能在任意地方使用mysql全套命令
echo "export PATH=${PATH}:${DIR}/${mysql_dir_name}/bin" > /etc/profile.d/mysql.sh
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
    echo -e "请务必在修改密码后将/etc/my.cnf的skip-grant-tables注释掉并重启mysql"
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