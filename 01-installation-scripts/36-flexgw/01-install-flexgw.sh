#!/bin/bash

src_dir=00src00

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
                echo_info 下载 $download_file_name 至 $(pwd)/
                # 检测是否有wget工具
                if [ ! -f /usr/bin/wget ];then
                    echo_info 安装wget工具
                    yum install -y wget
                fi
                wget $2
                if [ $? -ne 0 ];then
                    echo_error 下载 $2 失败！
                    exit 1
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
        exit 7
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


download_tar_gz ${src_dir} https://github.com/Ostaer/FlexGW/releases/download/v1.1/flexgw-1.1.0-1.el7.centos.x86_64.rpm
if [ $? -ne 0 ];then
    echo_error 下载rpm包失败，建议手动下载，下载完成后将rpm包上传至服务器 ${src_dir}/ 目录
    exit 1
fi


echo_info 调整内核参数
sysctl -a | egrep "ipv4.*(accept|send)_redirects" | awk -F "=" '{print $1"= 0"}' > /etc/sysctl.d/flexgw.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/flexgw.conf
sysctl -p

echo_info 安装依赖的软件包
# 检查epel包
yum repolist | grep "epel/x86_64" &> /dev/null
if [ $? -ne 0 ];then
    yum install -y epel-release
fi
yum install -y strongswan openvpn zip curl wget

echo_info 安装flexgw rpm包
rpm -ivh ${file_in_the_dir}/flexgw-1.1.0-1.el7.centos.x86_64.rpm

echo_info 初始化配置
cat > /usr/local/flexgw/rc/strongswan.conf << EOF
# strongswan.conf - strongSwan configuration file
#
# Refer to the strongswan.conf(5) manpage for details
#
# Configuration changes should be made in the included files

charon {
    load_modular = yes
    duplicheck {
           enable = yes
    }
    filelog {
        charon {
            path = /var/log/strongswan.charon.log
            append = no
            default = 1
            flush_line = yes
            ike_name = yes
            time_format = %b %e %T
        }
    }
    plugins {
        include strongswan.d/charon/*.conf
        stroke {
          timeout = 4000
        }
    }
}

include strongswan.d/*.conf
EOF
\cp -fv /usr/local/flexgw/rc/strongswan.conf /etc/strongswan/strongswan.conf
\cp -fv /usr/local/flexgw/rc/openvpn.conf /etc/openvpn/server/server.conf

echo_info 设置strongswan
sed -i "s|\s*load = yes|#&|g" /etc/strongswan/strongswan.d/charon/dhcp.conf
> /etc/strongswan/ipsec.secrets

echo_info 启动strongswan
systemctl start strongswan
systemctl enable strongswan
sleep 2
strongswan status

echo_info 启动openvpn
systemctl start openvpn-server@server &> /dev/null
systemctl enable openvpn-server@server

echo_info 初始化，大约耗时10秒中
/etc/init.d/initflexgw

echo_info 修复点击拨号vpn会出现500的错误
sed -i "s|                              'br': data\[4\], 'bs': data\[5\], 'ct': data\[7\]})|                              'br': data[4], 'bs': data[5], 'ct': data[8]})|" /usr/local/flexgw/website/vpn/dial/services.py
get_machine_ip

rm -rf /usr/local/bin/flexgw
ln -s /etc/init.d/flexgw /usr/local/bin/flexgw

echo_info flexgw启动成功
echo -e "\033[37m                  启动命令：\033[0m"
echo -e "\033[37m                  systemctl start strongswan\033[0m"
echo -e "\033[37m                  systemctl start openvpn-server@server\033[0m"
echo -e "\033[37m                  flexgw start\033[0m"
echo -e "\033[37m                  web ui访问地址：https://${machine_ip}/\033[0m"
echo -e "\033[37m                  账号密码：root/服务器root用户的密码\033[0m"