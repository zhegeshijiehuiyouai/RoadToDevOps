#!/bin/bash
# 为了提高完全性，使用虚拟用户而非系统用户登录

################用户信息配置#################
# 用于vsftpd的系统用户
sys_user=myftp
# 系统用户密码（仅在使用系统用户登录的时候生效）
sys_pass=9090960
# 系统用户的家目录目录
sys_user_home_dir=/data/vsftp-data

# 默认虚拟用户名
vir_user=my
# 默认虚拟用户密码
vir_pass=9090960
# 虚拟用户配置的目录（在/etc/vsfptd/下面）
vir_conf_dir=vsftpd_user_conf
# 密码文件名（/etc/vsftpd下面）
sec_file_name=mima

# 帮助文档名称（/etc/vsftpd下面）
help_doc=add_user.sh
########################################


function add_user_and_group(){
    if id -g ${1} >/dev/null 2>&1; then
        echo -e "\033[32m[#] ${1}组已存在，无需创建\033[0m"
    else
        groupadd ${1}
        echo -e "\033[32m[+] 创建${1}组\033[0m"
    fi
    if id -u ${2} >/dev/null 2>&1; then
        echo -e "\033[32m[#] ${2}用户已存在，无需创建\033[0m"
    else
        useradd -g ${1} -s /sbin/nologin -d ${3} ${2}
        echo -e "\033[32m[+] 创建${2}用户\033[0m"
    fi
}

function init_some(){
    
    echo -e "\033[32m[+] yum安装vsftpd\033[0m"
    yum install -y vsftpd
    echo -e "\033[32m[+] 检查数据目录是否存在\033[0m"
    [ -d ${sys_user_home_dir} ] || mkdir -p ${sys_user_home_dir}
    add_user_and_group ${sys_user} ${sys_user} ${sys_user_home_dir}/${sys_user}
    echo -e "\033[32m[+] 检查chroot_list是否存在\033[0m"
    [ -f /etc/vsftpd/chroot_list ] || touch /etc/vsftpd/chroot_list
}

# 使用系统用户登录的vsftp
function sys_user_vsftp(){
    init_some
    echo -e "\033[32m[>] 修改系统用户密码\033[0m"
    echo ${sys_pass} | passwd --stdin ${sys_user} &> /dev/null

    echo -e "\033[32m[>] 检查配置\033[0m"
    grep "\/sbin\/nologin" /etc/shells &> /dev/null
    if [ $? -ne 0 ];then
        echo "/sbin/nologin" >> /etc/shells
    fi

    sed -i 's/^#chroot_list_enable.*/chroot_list_enable=YES/' /etc/vsftpd/vsftpd.conf
    sed -i 's/^anonymous_enable=YES/anonymous_enable=NO/' /etc/vsftpd/vsftpd.conf
    echo "allow_writeable_chroot=YES" >> /etc/vsftpd/vsftpd.conf
    
    grep ${sys_user} /etc/vsftpd/chroot_list
    if [ $? -ne 0 ];then
cat >>/etc/vsftpd/chroot_list <<EOF
${sys_user}
EOF
    fi
    chmod 700 ${sys_user_home_dir}/${sys_user}
    systemctl restart vsftpd

    echo
    echo -e "\033[33m[>] vsftp已成功配置启动，详细信息如下：\033[0m"
    echo -e "\033[32m    与vsftp关联的系统用户：${sys_user}\033[0m"
    echo -e "\033[32m    系统用户密码：${sys_pass}\033[0m"
    echo -e "\033[32m    系统用户家目录：${sys_user_home_dir}\033[0m"

    echo -e "\033[36m[+] 创建-新增系统登录用户脚本：/etc/vsftpd/${help_doc}\033[0m"
cat >/etc/vsftpd/${help_doc} <<EOT
#!/bin/bash
# 新增系统用户脚本
if [ \$# -eq 0 ];then
    echo -e "\033[31m[*] 请输入要创建的用户名\033[0m"
    echo -e "\033[33m    Usage: sh \$0 用户名 密码\033[0m"
    exit 0
fi
if [ \$# -eq 1 ];then
    echo -e "\033[31m[*] 请输入要创建用户的密码\033[0m"
    echo -e "\033[33m    Usage: sh \$0 用户名 密码\033[0m"
    exit 0
fi
doc_vir_user=\$1
doc_vir_pass=\$2

function add_user_and_group(){
    if id -g \${1} >/dev/null 2>&1; then
        echo -e "\033[32m[#] \${1}组已存在，无需创建\033[0m"
    else
        groupadd \${1}
        echo -e "\033[32m[+] 创建\${1}组\033[0m"
    fi
    if id -u \${2} >/dev/null 2>&1; then
        echo -e "\033[32m[#] \${2}用户已存在，无需创建\033[0m"
    else
        useradd -g \${1} -s /sbin/nologin -d \${3} \${2}
        echo -e "\033[32m[+] 创建\${2}用户\033[0m"
    fi
}
add_user_and_group \$doc_vir_user \$doc_vir_user ${sys_user_home_dir}/\$doc_vir_user
echo \$doc_vir_pass | passwd --stdin \$doc_vir_user &> /dev/null

grep \$doc_vir_user /etc/vsftpd/chroot_list
if [ \$? -ne 0 ];then
cat >>/etc/vsftpd/chroot_list <<EOF
\$doc_vir_user
EOF
fi
chmod 700 ${sys_user_home_dir}/\$doc_vir_user

EOT
chmod +x /etc/vsftpd/${help_doc}
}



# 使用虚拟用户登录的vsftp
function virtual_user_vsftp() {
    init_some
    cd /etc/vsftpd
    echo -e "\033[32m[+] 创建虚拟用户密码文件\033[0m"

    # 密码文件，奇数行 为用户名，偶数行 为密码
cat >${sec_file_name}.txt <<EOF
${vir_user}
${vir_pass}
EOF

    db_load -T -t hash -f ${sec_file_name}.txt ${sec_file_name}.db
    chmod 600 ${sec_file_name}.db

    echo -e "\033[32m[+] 创建pam配置文件\033[0m"
    [ -f /etc/pam.d/vsftpd.bak ] || cp /etc/pam.d/vsftpd /etc/pam.d/vsftpd.bak

cat >/etc/pam.d/vsftpd <<EOF
auth sufficient /lib64/security/pam_userdb.so db=/etc/vsftpd/${sec_file_name}
account sufficient /lib64/security/pam_userdb.so db=/etc/vsftpd/${sec_file_name}
EOF

    echo -e "\033[32m[>] 调整vsftpd配置文件\033[0m"
    [ -f /etc/vsftpd/vsftpd.conf.bak ] || cp /etc/vsftpd/vsftpd.conf /etc/vsftpd/vsftpd.conf.bak

cat >/etc/vsftpd/vsftpd.conf <<EOF
#禁止匿名用户访问
anonymous_enable=NO
#允许本地用户登录FTP
local_enable=YES
#允许登陆用户有写权限
write_enable=YES
#设置本地用户的文件生成掩码为022，默认是077
local_umask=022
#激活目录信息,当远程用户更改目录时,将出现提示信息
dirmessage_enable=YES
#启用上传和下载日志功能
xferlog_enable=YES
#启用FTP数据端口的连接请求
connect_from_port_20=YES
#日志文件名和路径，默认值为/var/log/vsftpd.log
xferlog_file=/var/log/vsftpd.log
#使用标准的ftpd xferlog日志文件格式
xferlog_std_format=YES
#启用ASCII模式上传数据。默认值为NO
ascii_upload_enable=YES
#启用ASCII模式下载数据。默认值为NO
ascii_download_enable=YES
#使vsftpd处于独立启动监听端口模式
listen=YES
#启用虚拟用户
guest_enable=YES
#指定访问用户名
guest_username=${sys_user}
#设置PAM使用的名称，默认值为/etc/pam.d/vsftpd
pam_service_name=vsftpd
#设置用户配置文件所在的目录
user_config_dir=/etc/vsftpd/${vir_conf_dir}
#虚拟用户使用与本地用户相同的权限
virtual_use_local_privs=YES
#指定用户列表文件中的用户是否允许切换到上级目录。默认值为NO
chroot_local_user=NO
#启用chroot_list_file配置项指定的用户列表文件。默认值为NO
chroot_list_enable=YES
#指定用户列表文件，该文件用于控制哪些用户可以切换到用户家目录的上级目录
chroot_list_file=/etc/vsftpd/chroot_list
#设定chroot后，允许在chroot的根目录下写文件
allow_writeable_chroot=YES
EOF

    echo -e "\033[32m[+] 创建虚拟用户配置\033[0m"
    [ -d /etc/vsftpd/${vir_conf_dir} ] || mkdir -p /etc/vsftpd/${vir_conf_dir}

    if [ ! -f /etc/vsftpd/${vir_conf_dir}/${vir_user} ];then
cat >/etc/vsftpd/${vir_conf_dir}/${vir_user} <<EOF
#指定用户的家目录
local_root=${sys_user_home_dir}/${sys_user}/${vir_user}
#允许登陆用户有写权限
write_enable=YES
#允许登录用户下载文件
anon_world_readable_only=YES
#允许登录用户有上传文件（非目录）的权限
anon_upload_enable=YES
#允许登录用户创建目录的权限
anon_mkdir_write_enable=YES
#允许登录用户更多于上传或者建立目录之外的权限，如删除或者重命名
anon_other_write_enable=YES
EOF
    fi

    grep ${vir_user} /etc/vsftpd/chroot_list
    if [ $? -ne 0 ];then
cat >>/etc/vsftpd/chroot_list <<EOF
${vir_user}
EOF
    fi

    mkdir -p ${sys_user_home_dir}/${sys_user}/${vir_user}
    chown -R ${sys_user}:${sys_user} ${sys_user_home_dir}/${sys_user}
    chmod 700 ${sys_user_home_dir}/${sys_user}/${vir_user}

    systemctl restart vsftpd
    if [ $? -ne 0 ];then
        echo -e "\033[31m[*] vsftpd启动失败！请检查\033[0m"
        exit 1
    fi

    echo
    echo -e "\033[33m[>] vsftp已成功配置启动，详细信息如下：\033[0m"
    echo -e "\033[32m    与vsftp关联的系统用户：${sys_user}\033[0m"
    echo -e "\033[32m    系统用户家目录：${sys_user_home_dir}/${sys_user}\033[0m"
    echo -e "\033[32m    默认虚拟用户名：${vir_user}\033[0m"
    echo -e "\033[32m    默认虚拟用户密码：${vir_pass}\033[0m"
    echo -e "\033[32m    默认虚拟用户存储目录：${sys_user_home_dir}/${sys_user}/${vir_user}/\033[0m"

    echo -e "\033[36m[+] 创建-新增虚拟用户登录脚本：/etc/vsftpd/${help_doc}\033[0m"
cat >/etc/vsftpd/${help_doc} <<EOT
#!/bin/bash
# 新增虚拟用户脚本
if [ \$# -eq 0 ];then
    echo -e "\033[31m[*] 请输入要创建的用户名\033[0m"
    echo -e "\033[33m    Usage: sh \$0 用户名 密码\033[0m"
    exit 0
fi
if [ \$# -eq 1 ];then
    echo -e "\033[31m[*] 请输入要创建用户的密码\033[0m"
    echo -e "\033[33m    Usage: sh \$0 用户名 密码\033[0m"
    exit 0
fi
doc_vir_user=\$1
doc_vir_pass=\$2

grep \${doc_vir_user} /etc/vsftpd/${sec_file_name}.txt
if [ \$? -ne 0 ];then
cat >>/etc/vsftpd/${sec_file_name}.txt <<EOF
\$doc_vir_user
\$doc_vir_pass
EOF
else
    echo -e "\033[34m[*] 虚拟用户\$doc_vir_user已存在\033[0m"
    exit 0
fi
db_load -T -t hash -f /etc/vsftpd/${sec_file_name}.txt /etc/vsftpd/${sec_file_name}.db
chmod 600 /etc/vsftpd/${sec_file_name}.db

if [ ! -f /etc/vsftpd/${vir_conf_dir}/\$doc_vir_user ];then
cat >/etc/vsftpd/${vir_conf_dir}/\$doc_vir_user <<EOF
#指定用户的家目录
local_root=${sys_user_home_dir}/${sys_user}/\$doc_vir_user
#允许登陆用户有写权限
write_enable=YES
#允许登录用户下载文件
anon_world_readable_only=YES
#允许登录用户有上传文件（非目录）的权限
anon_upload_enable=YES
#允许登录用户创建目录的权限
anon_mkdir_write_enable=YES
#允许登录用户更多于上传或者建立目录之外的权限，如删除或者重命名
anon_other_write_enable=YES
EOF
fi

grep \$doc_vir_user /etc/vsftpd/chroot_list
if [ \$? -ne 0 ];then
cat >>/etc/vsftpd/chroot_list <<EOF
\$doc_vir_user
EOF
fi

mkdir -p ${sys_user_home_dir}/${sys_user}/\$doc_vir_user
chown -R ${sys_user}:${sys_user} ${sys_user_home_dir}/${sys_user}
chmod 700 ${sys_user_home_dir}/${sys_user}/\$doc_vir_user
EOT
chmod +x /etc/vsftpd/${help_doc}
}


function install_main_func(){
    read -p "请输入数字选择要安装类型（如需退出请输入q）：" software
    case $software in
        1)
            echo -e "\033[32m[!] 即将安装使用 \033[36m系统用户\033[32m 登录的vsftp\033[0m"
            # 等待两秒，给用户手动取消的时间
            sleep 2
            sys_user_vsftp
            ;;
        2)
            echo -e "\033[32m[!] 即将安装使用 \033[36m虚拟用户\033[32m 登录的vsftp\033[0m"
            sleep 2
            virtual_user_vsftp
            ;;
        q|Q)
            exit 0
            ;;
        *)
            install_main_func
            ;;
    esac
}

echo -e "\033[31m\n[?] 请选择使用哪种方式登录vsftp：\033[0m"
echo -e "\033[36m[1]\033[32m 系统用户登录"
echo -e "\033[36m[2]\033[32m 虚拟用户登录"
# 终止终端字体颜色
echo -e "\033[0m"
install_main_func

function install_lftp(){
    read -p "[?] 是否安装ftp客户端lftp（Y/n）：" yes_or_no
    case $yes_or_no in
        y|Y)
            echo -e "\033[32m[>] 安装lftp中，请耐心等待\033[0m"
            yum install -y lftp &> /dev/null
            if [ $? -eq 0 ];then
                echo -e "\033[32m[+] lftp安装成功！\033[0m"
            else
                echo -e "\033[31m[*] lftp安装出错，请检查\033[0m"
            fi
            ;;
        n|N)
            exit 0
            ;;
        *)
            install_lftp
            ;;
    esac
}

echo
install_lftp
