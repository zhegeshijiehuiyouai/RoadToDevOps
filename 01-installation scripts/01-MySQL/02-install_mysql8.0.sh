#!/bin/bash

# 脚本功能：自动部署mysql8.0
# 测试系统：CentOS7.4
# mysql安装文件：二进制包
#
# 将本脚本和二进制包放在同一目录下，脚本会在本目录下创建mysql作为mysql安装目录
#
# 本脚本默认会下载二进制包，如果自己上传，可以注释掉

# 部署目录
DIR=`pwd`
# 端口
PORT=3308
# 解压后的名字
FILE=mysql-8.0.17-el7-x86_64
# mysql二进制包名字
Archive=${FILE}.tar.gz

# 判断是否存在压缩包，没有的话就下载网易镜像站的mysql压缩包
ls ${Archive} &> /dev/null
[ $? -eq 0 ] || wget http://mirrors.163.com/mysql/Downloads/MySQL-8.0/${Archive}

# 解压
echo "解压中，请稍候..."
tar -zxf ${Archive} >/dev/null 2>&1
if [ $? -eq 0 ];then
    echo "解压完毕"
else
    echo "解压出错，请检查"
fi

# 做软连接，方便以后升级
ln -s ${FILE} mysql

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

mkdir -p ${DIR}/mysql/data
chown -R mysql:mysql ${DIR}/mysql/

# 初始化
cd mysql
bin/mysqld --initialize --basedir=${DIR}/mysql --datadir=${DIR}/mysql/data  --pid-file=${DIR}/mysql/data/mysql.pid >/dev/null 2>&1
echo "初始化完毕"
# 初始化完成后，data目录会生成文件，所以重新赋权
chown -R mysql:mysql ${DIR}/mysql/
echo "mysql目录授权成功"

# 如果原来有my.cnf，则备份原来的/etc/my.cnf
if [ -f /etc/my.cnf ];then
    mv /etc/my.cnf /etc/my.cnf_`date +%F`
    echo -e "\033[31m备份/etc/my.cnf_`date +%F`\033[0m"
fi

# 生成新的/etc/my.cnf
echo "初始化/etc/my.cnf..."
cat > /etc/my.cnf << EOF
[mysql]
default-character-set=utf8
socket=${DIR}/mysql/data/mysql.sock

[mysqld]
skip-grant-tables
port=${PORT}
socket=${DIR}/mysql/data/mysql.sock
basedir=${DIR}/mysql
datadir=${DIR}/mysql/data
max_connections=200
character-set-server=utf8
default-storage-engine=INNODB
max_allowed_packet=16M
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
ExecStart=${DIR}/mysql/support-files/mysql.server start
ExecStop=${DIR}/mysql/support-files/mysql.server stop
ExecRestart=${DIR}/mysql/support-files/mysql.server restart
ExecReload=${DIR}/mysql/support-files/mysql.server reload
PrivateTmp=true
[Install]
WantedBy=multi-user.target
EOF

# 将mysql文件拷贝到/usr/local/bin/，这样就能在任意地方使用mysql命令
if [ -f /usr/local/bin/mysql ];then
    rm -f /usr/local/bin/mysql
fi
cp ${DIR}/mysql/bin/mysql /usr/local/bin/

echo "设置完毕"
systemctl enable mysql.service >/dev/null 2>&1
systemctl start mysql.service
# mysql启动失败的话退出
if [ $? -ne 0 ];then
    echo -e "\n\033[31mmysql启动失败，请查看错误信息\033[0m\n"
    return 1
else
# 提供一些提示信息	
    echo -e "mysql已启动成功，端口号为：\033[32m${PORT}\033[0m\n"
    cat << EOF
mysql控制命令：
    启动：systemctl start mysql
    重启：systemctl restart mysql
    停止：systemctl stop mysql
EOF
    echo -e "\n\n请输入命令：mysql，进入MySQL修改密码"
    echo -e "首先将密码置空："
    echo -e "\033[32mmysql> use mysql;\033[0m"
    echo -e "\033[32mmysql> update user set authentication_string = '' where user = 'root';\033[0m"
    echo -e "\033[32mmysql> flush privileges;\033[0m"
    echo -e "\n请务必在修改密码后将/etc/my.cnf的skip-grant-tables注释掉并重启mysql"
    echo "然后修改密码，不修改将无法操作"
    echo -e "\n\033[32mmysql> ALTER USER 'root'@'localhost' IDENTIFIED BY '123456' PASSWORD EXPIRE NEVER; \033[0m"
    echo -e "\033[32mmysql> flush privileges;\033[0m"
    echo -e "\n\033[31m再次重启mysql\033[0m\n"
fi

