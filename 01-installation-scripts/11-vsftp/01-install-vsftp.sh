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
vir_user=myvuser
# 默认虚拟用户密码
vir_pass=fuza9090960
# 虚拟用户配置的目录（在/etc/vsfptd/下面）
vir_conf_dir=vsftpd_user_conf
# 密码文件名（/etc/vsftpd下面）
sec_file_name=mima

# 帮助文档名称（/etc/vsftpd下面）
help_doc=add_user.sh
########################################

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
        useradd -g ${1} -s /sbin/nologin -d ${2} ${1}
        echo_info 创建${1}用户
    fi
}

function init_some(){
    
    echo_info yum安装vsftpd
    yum install -y vsftpd
    echo_info 检查数据目录是否存在
    [ -d ${sys_user_home_dir} ] || mkdir -p ${sys_user_home_dir}
    add_user_and_group ${sys_user} ${sys_user_home_dir}/${sys_user}
    echo_info 检查chroot_list是否存在
    [ -f /etc/vsftpd/chroot_list ] || touch /etc/vsftpd/chroot_list
}

# 使用系统用户登录的vsftp
function sys_user_vsftp(){
    init_some
    echo_info 修改系统用户密码
    echo ${sys_pass} | passwd --stdin ${sys_user} &> /dev/null

    echo_info 检查配置
    grep "\/sbin\/nologin" /etc/shells &> /dev/null
    if [ $? -ne 0 ];then
        echo "/sbin/nologin" >> /etc/shells
    fi

    sed -i 's/^#chroot_list_enable.*/chroot_list_enable=YES/' /etc/vsftpd/vsftpd.conf
    sed -i 's/^anonymous_enable=YES/anonymous_enable=NO/' /etc/vsftpd/vsftpd.conf
    echo "allow_writeable_chroot=YES" >> /etc/vsftpd/vsftpd.conf
    echo "#pasv_min_port=10240 #（Default: 0 (use any port)） pasv使用的最小端口" >> /etc/vsftpd/vsftpd.conf
    echo "#pasv_max_port=20480 #（Default: 0 (use any port)） pasv使用的最大端口" >> /etc/vsftpd/vsftpd.conf
    
    grep ${sys_user} /etc/vsftpd/chroot_list
    if [ $? -ne 0 ];then
cat >>/etc/vsftpd/chroot_list <<EOF
${sys_user}
EOF
    fi
    chmod 700 ${sys_user_home_dir}/${sys_user}
    systemctl restart vsftpd

    echo_info vsftp已成功配置启动，详细信息如下：
    echo -e "\033[37m                  与vsftp关联的系统用户：${sys_user}\033[0m"
    echo -e "\033[37m                  系统用户密码：${sys_pass}\033[0m"
    echo -e "\033[37m                  系统用户家目录：${sys_user_home_dir}\033[0m"

    systemctl enable vsftpd

    echo_info 创建新增系统登录用户的脚本：/etc/vsftpd/${help_doc}
cat >/etc/vsftpd/${help_doc} <<EOT
#!/bin/bash
# 带格式的echo函数
function echo_info() {
    echo -e "[\033[36m\$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m\$@\033[0m"
}
function echo_warning() {
    echo -e "[\033[36m\$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m\$@\033[0m"
}
function echo_error() {
    echo -e "[\033[36m\$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m\$@\033[0m"
}

# 新增系统用户脚本
if [ \$# -eq 0 ];then
    echo_error 请输入要创建的用户名
    echo -e "\033[37m                  Usage: sh \$0 用户名 密码\033[0m"
    exit 0
fi
if [ \$# -eq 1 ];then
    echo_error 请输入要创建用户的密码
    echo -e "\033[37m                  Usage: sh \$0 用户名 密码\033[0m"
    exit 0
fi
doc_vir_user=\$1
doc_vir_pass=\$2

function add_user_and_group(){
    if id -g \${1} >/dev/null 2>&1; then
        echo_warning \${1}组已存在，无需创建
    else
        groupadd \${1}
        echo_info 创建\${1}组
    fi
    if id -u \${1} >/dev/null 2>&1; then
        echo_warning \${1}用户已存在，无需创建
    else
        useradd -g \${1} -s /sbin/nologin -d \${2} \${1}
        echo_info 创建\${1}用户
    fi
}

add_user_and_group \$doc_vir_user ${sys_user_home_dir}/\$doc_vir_user
echo \$doc_vir_pass | passwd --stdin \$doc_vir_user &> /dev/null

if [ \$? -ne 0 ];then
    echo_error 设置用户\$doc_vir_user的密码出错，请检查！
    exit 30
fi

grep \$doc_vir_user /etc/vsftpd/chroot_list
if [ \$? -ne 0 ];then
cat >>/etc/vsftpd/chroot_list <<EOF
\$doc_vir_user
EOF
fi
chmod 700 ${sys_user_home_dir}/\$doc_vir_user
if [ \$? -ne 0 ];then
    echo_error 修改权限失败，请检查！
    exit 30
fi
echo_info 用户\$doc_vir_user已成功创建

EOT
chmod +x /etc/vsftpd/${help_doc}
}



# 使用虚拟用户登录的vsftp
function virtual_user_vsftp() {
    init_some
    cd /etc/vsftpd
    echo_info 创建虚拟用户密码文件

    # 密码文件，奇数行 为用户名，偶数行 为密码
cat >${sec_file_name}.txt <<EOF
${vir_user}
${vir_pass}
EOF

    db_load -T -t hash -f ${sec_file_name}.txt ${sec_file_name}.db
    chmod 600 ${sec_file_name}.db

    echo_info 创建pam配置文件
    [ -f /etc/pam.d/vsftpd.bak ] || cp /etc/pam.d/vsftpd /etc/pam.d/vsftpd.bak

cat >/etc/pam.d/vsftpd <<EOF
auth sufficient /lib64/security/pam_userdb.so db=/etc/vsftpd/${sec_file_name}
account sufficient /lib64/security/pam_userdb.so db=/etc/vsftpd/${sec_file_name}
EOF

    echo_info 调整vsftpd配置文件
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
#pasv_min_port=10240 #（Default: 0 (use any port)） pasv使用的最小端口
#pasv_max_port=20480 #（Default: 0 (use any port)） pasv使用的最大端口
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

    echo_info 创建虚拟用户配置
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
        echo_error vsftpd启动失败，请检查！
        exit 1
    fi

    echo_info vsftp已成功配置启动，详细信息如下：
    echo -e "\033[37m                  与vsftp关联的系统用户：${sys_user}\033[0m"
    echo -e "\033[37m                  系统用户家目录：${sys_user_home_dir}/${sys_user}\033[0m"
    echo -e "\033[37m                  默认虚拟用户名：${vir_user}\033[0m"
    echo -e "\033[37m                  默认虚拟用户密码：${vir_pass}\033[0m"
    echo -e "\033[37m                  默认虚拟用户存储目录：${sys_user_home_dir}/${sys_user}/${vir_user}/\033[0m"

    systemctl enable vsftpd

    echo_info 创建新增虚拟用户登录的脚本：/etc/vsftpd/${help_doc}
cat >/etc/vsftpd/${help_doc} <<EOT
#!/bin/bash
# 带格式的echo函数
function echo_info() {
    echo -e "[\033[36m\$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m\$@\033[0m"
}
function echo_warning() {
    echo -e "[\033[36m\$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m\$@\033[0m"
}
function echo_error() {
    echo -e "[\033[36m\$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m\$@\033[0m"
}

# 新增虚拟用户脚本
if [ \$# -eq 0 ];then
    echo_error 请输入要创建的用户名
    echo -e "\033[37m                  Usage: sh \$0 用户名 密码\033[0m"
    exit 0
fi
if [ \$# -eq 1 ];then
    echo_error 请输入要创建用户的密码
    echo -e "\033[37m                  Usage: sh \$0 用户名 密码\033[0m"
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
    echo_error 虚拟用户\$doc_vir_user已存在
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

if [ \$? -ne 0 ];then
    echo_error 创建虚拟用户\$doc_vir_user失败，请检查！
    exit 30
fi
echo_info 虚拟用户\$doc_vir_user已成功创建

EOT
chmod +x /etc/vsftpd/${help_doc}
}


function install_main_func(){
    read -p "请输入数字选择要安装类型（如需退出请输入q）：" software
    case $software in
        1)
            echo_info 即将安装使用 系统用户 登录的vsftp
            # 等待1秒，给用户手动取消的时间
            sleep 1
            sys_user_vsftp
            ;;
        2)
            echo_info 即将安装使用 虚拟用户 登录的vsftp
            sleep 1
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

echo -e "\033[31m请选择使用哪种方式登录vsftp：\033[0m"
echo -e "\033[36m[1]\033[32m 系统用户登录\033[0m"
echo -e "\033[36m[2]\033[32m 虚拟用户登录\033[0m"
install_main_func

function install_lftp(){
    read -p "是否安装ftp客户端lftp（Y/n）：" yes_or_no
    case $yes_or_no in
        y|Y)
            echo_info 安装lftp中，请耐心等待
            yum install -y lftp &> /dev/null
            if [ $? -eq 0 ];then
                echo_info lftp安装成功！
            else
                echo_error lftp安装出错，请检查
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

install_lftp
