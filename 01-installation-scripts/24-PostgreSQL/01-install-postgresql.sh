#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
postgresql_port=5432
# 请保持下面两个大版本号一致，这里大版本都是11
postgresql_version_yum=11
postgresql_version_src=11.12
mydir=$(pwd)
# 部署postgre的目录
postgresql_home=$(pwd)/postgresql-${postgresql_version_yum}
sys_user=postgres
unit_file_name=postgresql-${postgresql_version_yum}.service


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

# 这次的函数添加的用户是可登录的
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
        useradd -g ${1} -s /bin/bash ${1}
        echo_info 创建${1}用户
    fi
}

# 解压
function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
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

function config_tune() {
    echo_info 配置postgresql命令提示符
    echo "\set PROMPT1 '%[%033[1;33;40m%]%n@%/%[%033[0m%=>%] '" > ~/.psqlrc
    echo "\set PROMPT2 '%[%033[1;33;40m%]>%[%033[0m%] '" >> ~/.psqlrc
    echo "\set PROMPT1 '%[%033[1;33;40m%]%n@%/%[%033[0m%=>%] '" > /home/${sys_user}/.psqlrc
    echo "\set PROMPT2 '%[%033[1;33;40m%]>%[%033[0m%] '" >> /home/${sys_user}/.psqlrc
    chown -R ${sys_user}:${sys_user} /home/${sys_user}/.psqlrc

    echo_info 设置非postgres用户也可以登录数据库
    grep -E "^# peer改为trust，不用切换用户postgres就可以登录" ${PG_CONFIG_FILE_CONN} &> /dev/null
    if [ $? -ne 0 ];then
        sed -i '/# "local" is for Unix domain socket connections only/a # peer改为trust，不用切换用户postgres就可以登录' ${PG_CONFIG_FILE_CONN}
    fi
    sed -i 's/local[[:space:]]\+all[[:space:]]\+all[[:space:]]\+peer/local   all             all                                     trust/g' ${PG_CONFIG_FILE_CONN}
    
    echo_info 配置外部地址能访问postgresql
    grep -E "^listen_addresses[[:space:]]*=[[:space:]]*'\*'" ${PG_CONFIG_FILE_PARAM} &> /dev/null
    if [ $? -ne 0 ];then
        sed -i '/# - Connection Settings -/a listen_addresses = '\'*\''' ${PG_CONFIG_FILE_PARAM}
    fi
    sed -i 's/^#password_encryption = on/password_encryption = on/g' ${PG_CONFIG_FILE_PARAM}
    grep -E "^host[[:space:]]+all[[:space:]]+all[[:space:]]+0.0.0.0/0[[:space:]]+md5" ${PG_CONFIG_FILE_CONN} &> /dev/null
    if [ $? -ne 0 ];then
        sed -i '/# IPv4 local connections:/a host    all             all             0.0.0.0/0               md5' ${PG_CONFIG_FILE_CONN}
    fi
    echo_info 设置postgresql端口
    grep -E "^port[[:space:]]*=[[:space:]]*5432" ${PG_CONFIG_FILE_PARAM} &> /dev/null
    if [ $? -ne 0 ];then
        sed -i '/^#port[[:space:]]\+=[[:space:]]\+5432[[:space:]]\+#/a port = '${postgresql_port}'' ${PG_CONFIG_FILE_PARAM}
    fi
}

function install_postgresql_by_yum() {
    echo_info 安装浙大 postgresql 源
    rpm -Uvh http://mirrors.zju.edu.cn/postgresql/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

    echo_info 安装PostgreSQL ${postgresql_version_yum}
    yum install -y postgresql${postgresql_version_yum}-server

    echo_info 配置数据目录
    mkdir -p ${postgresql_home}
    mv /var/lib/pgsql/* ${postgresql_home}/
    chown -R postgres:postgres ${postgresql_home}
    rm -rf /var/lib/pgsql
    ln -s ${postgresql_home} /var/lib/pgsql
    chown -R postgres:postgres /var/lib/pgsql

    echo_info 初始化postgresql
    postgresql-${postgresql_version_yum}-setup initdb
    echo_info 启动postgresql
    systemctl start postgresql-${postgresql_version_yum}

    PG_CONFIG_FILE_PARAM=/var/lib/pgsql/${postgresql_version_yum}/data/postgresql.conf
    PG_CONFIG_FILE_CONN=/var/lib/pgsql/${postgresql_version_yum}/data/pg_hba.conf
    config_tune

    echo_info 重启postgresql
    systemctl daemon-reload
    systemctl restart postgresql-${postgresql_version_yum}

    echo_info postgresql已部署完毕并成功启动，以下是相关信息：
    echo -e "\033[37m                  端口：${postgresql_port}\033[0m"
    echo -e "\033[37m                  启动命令：systemctl start postgresql-${postgresql_version_yum}\033[0m"
    if [ ${postgresql_port} -ne 5432 ];then
        echo -e "\033[37m                  登录命令：psql -U postgres -p ${postgresql_port} [-d postgres]\033[0m"
    else
        echo -e "\033[37m                  登录命令：psql -U postgres [-d postgres]\033[0m"
    fi
}

function generate_unit_file() {
cat > /usr/lib/systemd/system/${unit_file_name} << EOF
[Unit]
Description=PostgreSQL ${postgresql_version_yum} database server
After=network.target

[Service]
Type=forking

User=${sys_user}
Group=${sys_user}

# Note: avoid inserting whitespace in these Environment= lines, or you may
# break postgresql-setup.

# Location of database directory
Environment=PGDATA=${postgresql_home}/data

# Disable OOM kill on the postmaster
OOMScoreAdjust=-1000
Environment=PG_OOM_ADJUST_FILE=/proc/self/oom_score_adj
Environment=PG_OOM_ADJUST_VALUE=0

ExecStart=${postgresql_home}/bin/pg_ctl start -D \${PGDATA} -s -l ${postgresql_home}/logs/logfile
ExecStop=${postgresql_home}/bin/pg_ctl stop -D \${PGDATA} -s -m fast
ExecReload=${postgresql_home}/bin/pg_ctl reload -D \${PGDATA} -s

[Install]
WantedBy=multi-user.target
EOF
}

# 多核编译
function multi_core_compile(){
    echo_info 多核编译
    assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
    cpucores=$(cat /proc/cpuinfo | grep -c processor)
    compilecore=$(($cpucores - $assumeused - 1))
    if [ $compilecore -ge 1 ];then
        make -j $compilecore && make -j $compilecore install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi
    else
        make && make install
        if [ $? -ne 0 ];then
            echo_error 编译安装出错，请检查脚本
            exit 1
        fi 
    fi
}

function install_postgresql_by_src() {
    echo_info 安装编译工具
    yum install -y gcc make readline readline-devel zlib zlib-devel
    download_tar_gz ${src_dir} https://ftp.postgresql.org/pub/source/v${postgresql_version_src}/postgresql-${postgresql_version_src}.tar.gz
    cd ${file_in_the_dir}
    untar_tgz postgresql-${postgresql_version_src}.tar.gz
    cd postgresql-${postgresql_version_src}
    ./configure --prefix=${postgresql_home}
    multi_core_compile
    add_user_and_group ${sys_user}
    
    mkdir -p ${postgresql_home}/{data,logs}
    echo_info postgresql目录授权
    chown -R ${sys_user}:${sys_user} ${postgresql_home}
    
    echo_info 设置环境变量
    cat > /etc/profile.d/postgresql.sh << EOF
export PGHOME=${postgresql_home}
export PGDATA=${postgresql_home}/data
export PATH=\$PGHOME/bin:\$PATH
export MANPATH=\$PGHOME/share/man:\$MANPATH
export LANG=en_US.utf8
export DATE='`date +"%Y-%m-%d %H:%M:%S"`'
export LD_LIBRARY_PATH=\$PGHOME/lib:\$LD_LIBRARY_PATH
EOF
    source /etc/profile

    su - ${sys_user} << EOF
echo_info 初始化数据库
initdb -D ${postgresql_home}/data
echo_info 启动postgresql
pg_ctl -D ${postgresql_home}/data -l ${postgresql_home}/logs/logfile start
EOF

    PG_CONFIG_FILE_PARAM=${postgresql_home}/data/postgresql.conf
    PG_CONFIG_FILE_CONN=${postgresql_home}/data/pg_hba.conf
    config_tune

    generate_unit_file
    systemctl daemon-reload

    echo_info 设置开机启动
    systemctl enable ${unit_file_name}

    echo_info 重启postgresql
    # 非systemd启动，所以使用命令关闭
    su - ${sys_user} << EOF
pg_ctl stop -D ${postgresql_home}/data -s
EOF

    systemctl start ${unit_file_name}
    if [ $? -eq 0 ];then
        echo_info postgresql已部署完毕并成功启动，以下是相关信息：
        echo -e "\033[37m                  端口：${postgresql_port}\033[0m"
        echo -e "\033[37m                  启动命令：systemctl start ${unit_file_name}\033[0m"
        if [ ${postgresql_port} -ne 5432 ];then
            echo -e "\033[37m                  登录命令：psql -U postgres -p ${postgresql_port} [-d postgres]\033[0m"
        else
            echo -e "\033[37m                  登录命令：psql -U postgres [-d postgres]\033[0m"
        fi
    else
        echo_error postgresql启动失败
        exit 10
    fi
    echo_warning 由于bash特性限制，在本终端使用psql等命令，需先执行 source /etc/profile 加载环境变量，或者新开一个终端自动加载环境变量
}

function is_run_postgresql() {
    ps -ef | grep "postgres" | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到postgresql正在运行中，退出
        exit 1
    fi
    if [ -d ${postgresql_home} ];then
        echo_error 检测到postgresql部署目录${postgresql_home}，请确认是否重复安装
        exit 2
    fi
    if [ -d /var/lib/pgsql ];then
        file_num=$(ls /var/lib/pgsql/ | wc -l)
        if [ file_num -ne 0 ];then
            echo_error 检测到postgresql部署目录/var/lib/pgsql，请确认是否重复安装
            exit 3
        fi
    fi
}

function install_main_func(){
    read -p "请输入数字选择安装类型（如需退出请输入q）：" software
    case $software in
        1)
            echo_info 即将使用 yum 部署postgresql
            # 等待1秒，给用户手动取消的时间
            sleep 1
            install_postgresql_by_yum
            ;;
        2)
            echo_info 即将使用 源码编译 部署postgresql
            sleep 1
            install_postgresql_by_src
            ;;
        q|Q)
            exit 0
            ;;
        *)
            install_main_func
            ;;
    esac
}

is_run_postgresql

echo -e "\033[31m本脚本支持两种部署方式：\033[0m"
echo -e "\033[36m[1]\033[32m yum部署postgresql\033[0m"
echo -e "\033[36m[2]\033[32m 源码编译部署postgresql\033[0m"
install_main_func