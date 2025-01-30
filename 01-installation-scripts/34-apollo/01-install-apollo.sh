#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
my_dir=$(pwd)
############# 二进制包部署配置 ###############
apollo_version=2.2.0
port_portal=8070
port_config=8080
port_admin=8090
# docker-compose启动时，是docker-compose的家目录
# 二进制包部署时，是portal、config、admin的家目录
apollo_home=apollo
# 数据库连接配置
portal_mysql_url=10.211.55.13
portal_mysql_port=3306
portal_mysql_user=root
portal_mysql_pass=yourpassword
portal_mysql_db=ApolloPortalDB
# config和admin共用数据库
config_admin_mysql_url=10.211.55.13
config_admin_mysql_port=3306
config_admin_mysql_user=root
config_admin_mysql_pass=yourpassword
config_admin_mysql_db=ApolloConfigDB
# 启动apollo的用户
sys_user=apollo



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
function check_downloadfile() {
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IksS $1 | head -1 | awk '{print $2}')
    if [ $http_code -eq 404 ];then
        echo_error $1
        echo_error 服务端文件不存在，退出
        exit 98
    fi
}
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
                if [[ $os == "centos" ]];then
                    yum install -y wget
                elif [[ $os == "ubuntu" ]];then
                    apt install -y wget
                elif [[ $os == 'rocky' || $os == 'alma' ]];then
                    dnf install -y wget
                fi
            fi
            check_downloadfile $2
            wget --no-check-certificate $2
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
                    if [[ $os == "centos" ]];then
                        yum install -y wget
                    elif [[ $os == "ubuntu" ]];then
                        apt install -y wget
                    elif [[ $os == 'rocky' || $os == 'alma' ]];then
                        dnf install -y wget
                    fi
                fi
                check_downloadfile $2
                wget --no-check-certificate $2
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

#--------
function input_machine_ip_fun() {
    read -e input_machine_ip
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
#--------

function check_docker() {
    docker -v &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到docker，请先部署docker，参考部署脚本：
        echo https://github.com/zhegeshijiehuiyouai/RoadToDevOps/blob/master/01-installation-scripts/04-Docker/01-install-docker.sh
        exit 1
    fi
}

function docker_compose_start_apollo() {
    echo_info 启动apollo
    docker-compose up -d
    get_machine_ip
    docker-compose ps -a
    echo_info 访问地址：http://${machine_ip}:${port_portal}
    echo -e "\033[37m                  默认账号：apollo\033[0m"
    echo -e "\033[37m                  默认密码：admin\033[0m"
    echo -e "\033[37m                  mysql用户名为root，密码为空\033[0m"
    exit 0
}

function check_port() {
    # 用法：check_port 端口1 端口2 端口3 ...
    echo_info 端口检测
    for port in $@;do
        ss -tnlp | grep ":${port} " &> /dev/null
        if [ $? -eq 0 ];then
            if [ ${apollo_exist} -eq 1 ];then
                echo_error 端口 ${port} 已被占用，请修改 docker-compose.yaml文件后启动服务
                exit 1
            else
                echo_error 端口 ${port} 已被占用，请在脚本中修改端口后再执行
                exit 1
            fi
        fi
    done
}

function get_docker_compose_port() {
    port_portal=$(grep ":8070" docker-compose.yml | awk -F'"' '{print $2}' | awk -F':' '{print $1}')
    port_config=$(grep ":8080" docker-compose.yml | awk -F'"' '{print $2}' | awk -F':' '{print $1}')
    port_admin=$(grep ":8090" docker-compose.yml | awk -F'"' '{print $2}' | awk -F':' '{print $1}')
}

function check_unzip() {
    unzip -h &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装unzip
        yum install -y unzip
        if [ $? -ne 0 ];then
            echo_error unzip安装失败，请排查原因
            exit 2
        fi
    fi
}

function install_by_docker() {
    # 如果有apollo目录，就检查一下apollo是否启动了
    if [ -d apollo ];then
        apollo_exist=1    # 这个变量的作用是，针对docker-compose版本的apollo已存在的情况下，在check_port中使用不同的文案
        cd ${my_dir}/${apollo_home}
        docker-compose ps -a | grep appolo &> /dev/null
        if [ $? -eq 0 ];then
            echo_info apollo已启动
            exit 0
        else
            get_docker_compose_port
            check_port ${port_portal} ${port_config} ${port_admin}
            docker_compose_start_apollo
        fi
    fi

    check_port ${port_portal} ${port_config} ${port_admin}
    check_docker
    echo_info 下载apollo

    if [ -f apollo-master.zip ];then
        file_in_the_dir=$(pwd)
    elif [ -f ${src_dir}/apollo-master.zip ];then
        file_in_the_dir=${src_dir}
        cd ${file_in_the_dir}
    else
        download_tar_gz ${src_dir} https://cors.isteed.cc/https://github.com/apolloconfig/apollo/archive/refs/heads/master.zip
        if [ $? -ne 0 ];then
            echo_error 下载失败，可重试或手动下载压缩包放于当前目录，再运行本脚本
            echo https://github.com/apolloconfig/apollo/archive/refs/heads/master.zip
            exit 3
        fi
        cd ${file_in_the_dir}
        mv master.zip apollo-master.zip
    fi

    check_unzip

    echo info 解压apollo压缩包
    unzip apollo-master.zip &> /dev/null

    echo_info 提取docker-compose启动文件
    mv apollo-master/scripts/docker-quick-start ${my_dir}/${apollo_home}
    echo_info 配置持久化
    sed -i 's#/var/lib/mysql#./mysql-data:/var/lib/mysql#g' ${my_dir}/${apollo_home}/docker-compose.yml
    echo_info 配置端口映射
    sed -i 's#".*:8080"#"'${port_portal}':8070"#g' ${my_dir}/${apollo_home}/docker-compose.yml
    sed -i 's#".*:8080"#"'${port_config}':8080"#g' ${my_dir}/${apollo_home}/docker-compose.yml
    sed -i 's#".*:8080"#"'${port_admin}':8090"#g' ${my_dir}/${apollo_home}/docker-compose.yml
    echo_info 清理临时文件
    rm -rf apollo-master

    docker_compose_start_apollo
}

function check_jdk() {
    echo_info jdk检测
    java -version &> /dev/null
    if [ $? -ne 0 ];then
        echo_error 未检测到jdk，请先部署jdk
        exit 1
    fi
}

function check_dir() {
    echo_info 目录检测
    if [ -d ${my_dir}/${apollo_home} ];then
        if [ ${USER_INPUT_INSTALL} -eq 2 ];then
            echo_warning 检测到目录 ${my_dir}/${apollo_home}，服务器可能已部署apollo，请检查是否重复部署
            exit 2
        elif [ ${USER_INPUT_INSTALL} -eq 3 ];then
            if [ -d ${my_dir}/${apollo_home}/apollo-portal ];then
                echo_warning 检测到目录 ${my_dir}/${apollo_home}/apollo-portal，服务器可能已部署apollo-portal，请检查是否重复部署
                exit 2
            fi
        elif [ ${USER_INPUT_INSTALL} -eq 4 ];then
            if [ -d ${my_dir}/${apollo_home}/apollo-configservice ];then
                echo_warning 检测到目录 ${my_dir}/${apollo_home}/apollo-configservice，服务器可能已部署apollo-configservice，请检查是否重复部署
                exit 2
            fi
            if [ -d ${my_dir}/${apollo_home}/apollo-adminservice ];then
                echo_warning 检测到目录 ${my_dir}/${apollo_home}/apollo-adminservice，服务器可能已部署apollo-adminservice，请检查是否重复部署
                exit 2
            fi
        fi
    else
        echo_info 创建目录 ${my_dir}/${apollo_home}
        mkdir -p ${my_dir}/${apollo_home}
    fi
}

function check_mysql() {
    # 用法：check_mysql 地址 端口 用户名 密码
    mysql -V &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装mysql客户端
        yum install -y mysql
        if [ $? -ne 0 ];then
            echo_error mysql客户端安装失败
            exit 3
        fi
    fi
    version=$(mysql -h$1 -P$2 -u$3 -p$4 -e 'select version();' 2>/dev/null | grep "5")
    if [ $? -ne 0 ];then
        echo ${version} | grep "^8" &> /dev/null
        if [ $? -eq 0 ];then
            true
        else
            echo_error mysql $1:$2 连接失败
            exit 1
        fi
    else
        version_2nd=$(echo ${version} | awk -F"." '{print $2}')
        version_3rd=$(echo ${version} | awk -F"." '{print $3}')
        if [ ${version_2nd} -lt 6 ];then
            echo_error mysql版本过低，需要5.6.5以上的版本
            exit 1
        elif [ ${version_2nd} -eq 6 ];then
            if [ ${version_3rd} -lt 5 ];then
                echo_error mysql版本过低，需要5.6.5以上的版本
                exit 1          
            fi
        fi
    fi
}

function preinstall() {
    check_jdk
    check_dir
    check_unzip
    add_user_and_group ${sys_user}
}

function init_mysql() {
    # 用法：init_mysql [portal|config_admin]，根据参数初始化portal或者configservice和adminservice
    if [[ $1 == "portal" ]];then
        download_tar_gz ${src_dir} https://cors.isteed.cc/https://raw.githubusercontent.com/apolloconfig/apollo/master/scripts/sql/apolloportaldb.sql
        echo_info 初始化apolloportaldb
        sed -i "s@CREATE DATABASE IF NOT EXISTS .* DEFAULT CHARACTER SET = utf8mb4;@CREATE DATABASE IF NOT EXISTS ${portal_mysql_db} DEFAULT CHARACTER SET = utf8mb4;@g" ${file_in_the_dir}/apolloportaldb.sql
        sed -i "s@Use .*;@Use ${portal_mysql_db};@g" ${file_in_the_dir}/apolloportaldb.sql
        mysql -h${portal_mysql_url} -P${portal_mysql_port} -u${portal_mysql_user} -p${portal_mysql_pass} -e "source ${file_in_the_dir}/apolloportaldb.sql" &> /dev/null
    elif [[ $1 == "config_admin" ]];then
        download_tar_gz ${src_dir} https://cors.isteed.cc/https://raw.githubusercontent.com/apolloconfig/apollo/master/scripts/sql/apolloconfigdb.sql
        echo_info 初始化apolloconfigdb
        sed -i "s@CREATE DATABASE IF NOT EXISTS .* DEFAULT CHARACTER SET = utf8mb4;@CREATE DATABASE IF NOT EXISTS ${config_admin_mysql_db} DEFAULT CHARACTER SET = utf8mb4;@g" ${file_in_the_dir}/apolloconfigdb.sql
        sed -i "s@Use .*;@Use ${config_admin_mysql_db};@g" ${file_in_the_dir}/apolloconfigdb.sql
        mysql -h${config_admin_mysql_url} -P${config_admin_mysql_port} -u${config_admin_mysql_user} -p${config_admin_mysql_pass} -e "source ${file_in_the_dir}/apolloconfigdb.sql" &>/dev/null
    fi
}

function is_init_portal_mysql() {
    echo_warning "是否初始化portal数据库？默认不初始化 [y|N]"
    read -e USER_INPUT
    if [ ! -z ${USER_INPUT} ];then
        case ${USER_INPUT} in
            y|Y|yes)
                init_mysql portal
                ;;
            n|N|no)
                true
                ;;
            *)
                is_init_portal_mysql
                ;;
        esac
    fi
}

function is_init_config_admin_mysql() {
    echo_warning "是否初始化config/admin数据库？默认不初始化 [y|N]"
    read -e USER_INPUT
    if [ ! -z ${USER_INPUT} ];then
        case ${USER_INPUT} in
            y|Y|yes)
                init_mysql config_admin
                ;;
            n|N|no)
                true
                ;;
            *)
                is_init_config_admin_mysql
                ;;
        esac
    fi
}

function download_binary_zip() {
    # 用法：download_binary_zip [portal|config_admin]，根据参数下载portal或者configservice和adminservice
    if [[ $1 == "portal" ]];then
        download_tar_gz ${src_dir} https://cors.isteed.cc/https://github.com/apolloconfig/apollo/releases/download/v${apollo_version}/apollo-portal-${apollo_version}-github.zip
        cd ${file_in_the_dir}
        echo_info 解压 apollo-portal-${apollo_version}-github.zip
        unzip apollo-portal-${apollo_version}-github.zip -d apollo-portal &> /dev/null
        mv apollo-portal ${my_dir}/${apollo_home}
    elif [[ $1 == "config_admin" ]];then
        download_tar_gz ${src_dir} https://cors.isteed.cc/https://github.com/apolloconfig/apollo/releases/download/v${apollo_version}/apollo-configservice-${apollo_version}-github.zip
        download_tar_gz ${src_dir} https://cors.isteed.cc/https://github.com/apolloconfig/apollo/releases/download/v${apollo_version}/apollo-adminservice-${apollo_version}-github.zip
        cd ${file_in_the_dir}
        echo_info 解压 apollo-configservice-${apollo_version}-github.zip
        unzip apollo-configservice-${apollo_version}-github.zip -d apollo-configservice &> /dev/null
        echo_info 解压 apollo-adminservice-${apollo_version}-github.zip
        unzip apollo-adminservice-${apollo_version}-github.zip -d apollo-adminservice &> /dev/null
        mv apollo-configservice ${my_dir}/${apollo_home}
        mv apollo-adminservice ${my_dir}/${apollo_home}
    fi
}

function check_ip_legal() {
    if [[ "${1}" == "" ]];then
        USER_INPUT=${machine_ip}
    else
        if [[ ! ${1} =~ ^([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))(\.([0,1]?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))){3} ]];then
            echo_error "错误的ip格式(${1})，请重新输入"
            input_apollo_config_admin_ip
        fi
    fi
}

function input_apollo_config_admin_ip() {
    get_machine_ip
    echo_info 请输入 apollo-configservice / apollo-adminservice 的IP地址，默认为 ${machine_ip} ：
    read -e USER_INPUT
    check_ip_legal ${USER_INPUT}
    apollo_config_admin_ip=${USER_INPUT}
}

function config_apollo() {
    # 用法：config_apollo [portal|config_admin]，根据参数配置portal或者configservice和adminservice
    if [[ $1 == "portal" ]];then
        cd ${my_dir}/${apollo_home}/apollo-portal
        input_apollo_config_admin_ip
        # 端口
        sed -i "s/^SERVER_PORT=.*/SERVER_PORT=${port_portal}/" scripts/startup.sh
        # 日志目录
        [ -d logs ] || mkdir logs
        sed -i "s@^LOG_FOLDER=.*@LOG_FOLDER=${my_dir}/${apollo_home}/apollo-portal/logs@g" apollo-portal.conf
        sed -i "s@^LOG_DIR=.*@LOG_DIR=${my_dir}/${apollo_home}/apollo-portal/logs@g" scripts/startup.sh
        # 数据库连接
        sed -i "s@^spring.datasource.url.*@spring.datasource.url = jdbc:mysql://${portal_mysql_url}:${portal_mysql_port}/${portal_mysql_db}?characterEncoding=utf8@g" config/application-github.properties
        sed -i "s@^spring.datasource.username.*@spring.datasource.username = ${portal_mysql_user}@g" config/application-github.properties
        sed -i "s@^spring.datasource.password.*@spring.datasource.password = ${portal_mysql_pass}@g" config/application-github.properties
        # portal对接的环境
        sed -i "s@^[a-z].*@# &@g" config/apollo-env.properties
        echo "dev.meta=http://${apollo_config_admin_ip}:${port_config}" >> config/apollo-env.properties

        echo_warning portal环境仅设置了dev，如需要多环境，请参照以下步骤
        echo_warning 步骤1：部署一套新的apollo-configservice、apollo-adminservice
        echo_warning 步骤2：编辑配置文件 ${my_dir}/${apollo_home}/apollo-portal/config/apollo-env.properties，新增环境
        echo_warning 步骤3：
        echo_warning "(旧版、新版都可以)修改ApolloPortal数据库-->serverconfig表-->apollo.portal.envs字段 添加新环境名称，用逗号分隔"
        echo_warning "(新版新增渠道)登录portal，点击右上角管理员工具-->系统参数(报Whitelabel Error Page的话，需要清除浏览器缓存)-->编辑[PortalDB配置管理]下的apollo.portal.envs-->添加新环境名称，用逗号分隔"
        echo_warning 步骤4：重启apollo-portal
        echo
        echo "portal环境仅设置了dev，如需要多环境，请参照以下步骤" > ${my_dir}/${apollo_home}/apollo-portal/配置多环境.txt
        echo "步骤1：部署一套新的apollo-configservice、apollo-adminservice" >> ${my_dir}/${apollo_home}/apollo-portal/配置多环境.txt
        echo "步骤2：编辑配置文件 ${my_dir}/${apollo_home}/apollo-portal/config/apollo-env.properties，新增环境" >> ${my_dir}/${apollo_home}/apollo-portal/配置多环境.txt
        echo "步骤3：" >> ${my_dir}/${apollo_home}/apollo-portal/配置多环境.txt
        echo "(旧版、新版都可以)修改ApolloPortal数据库-->serverconfig表-->apollo.portal.envs字段 添加新环境名称，用逗号分隔" >> ${my_dir}/${apollo_home}/apollo-portal/配置多环境.txt
        echo "(新版新增渠道)登录portal，点击右上角管理员工具-->系统参数(报Whitelabel Error Page的话，需要清除浏览器缓存)-->编辑[PortalDB配置管理]下的apollo.portal.envs-->添加新环境名称，用逗号分隔" >> ${my_dir}/${apollo_home}/apollo-portal/配置多环境.txt
        echo "步骤4：重启apollo-portal" >> ${my_dir}/${apollo_home}/apollo-portal/配置多环境.txt
        echo_info 上述步骤已生成到 ${my_dir}/${apollo_home}/apollo-portal/配置多环境.txt
        echo

    elif [[ $1 == "config_admin" ]];then
        # -----------配置apollo-configservice
        cd ${my_dir}/${apollo_home}/apollo-configservice
        # 端口
        sed -i "s/^SERVER_PORT=.*/SERVER_PORT=${port_config}/" scripts/startup.sh
        # 日志目录
        [ -d logs ] || mkdir logs
        sed -i "s@^LOG_FOLDER=.*@LOG_FOLDER=${my_dir}/${apollo_home}/apollo-configservice/logs@g" apollo-configservice.conf
        sed -i "s@^LOG_DIR=.*@LOG_DIR=${my_dir}/${apollo_home}/apollo-configservice/logs@g" scripts/startup.sh
        # 数据库连接
        sed -i "s@^spring.datasource.url.*@spring.datasource.url = jdbc:mysql://${config_admin_mysql_url}:${config_admin_mysql_port}/${config_admin_mysql_db}?characterEncoding=utf8@g" config/application-github.properties
        sed -i "s@^spring.datasource.username.*@spring.datasource.username = ${config_admin_mysql_user}@g" config/application-github.properties
        sed -i "s@^spring.datasource.password.*@spring.datasource.password = ${config_admin_mysql_pass}@g" config/application-github.properties

        # -----------配置apollo-adminservice
        cd ${my_dir}/${apollo_home}/apollo-adminservice
        # 端口
        sed -i "s/^SERVER_PORT=.*/SERVER_PORT=${port_admin}/" scripts/startup.sh
        # 日志目录
        [ -d logs ] || mkdir logs
        sed -i "s@^LOG_FOLDER=.*@LOG_FOLDER=${my_dir}/${apollo_home}/apollo-adminservice/logs@g" apollo-adminservice.conf
        sed -i "s@^LOG_DIR=.*@LOG_DIR=${my_dir}/${apollo_home}/apollo-adminservice/logs@g" scripts/startup.sh
        # 数据库连接
        sed -i "s@^spring.datasource.url.*@spring.datasource.url = jdbc:mysql://${config_admin_mysql_url}:${config_admin_mysql_port}/${config_admin_mysql_db}?characterEncoding=utf8@g" config/application-github.properties
        sed -i "s@^spring.datasource.username.*@spring.datasource.username = ${config_admin_mysql_user}@g" config/application-github.properties
        sed -i "s@^spring.datasource.password.*@spring.datasource.password = ${config_admin_mysql_pass}@g" config/application-github.properties        
    fi
}

function generate_unit_file() {
    # 用法：generate_unit_file [portal|config_admin]，根据参数生成unitfile
    if [[ $1 == "portal" ]];then
        echo_info 生成apollo-portal.service文件用于systemd控制
        cat >/etc/systemd/system/apollo-portal.service <<EOF
[Unit]
Description=Apollo Portal, install script from https://github.com/zhegeshijiehuiyouai/RoadToDevOps
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
User=${sys_user}
Group=${sys_user}
Type=forking
ExecStart=/bin/bash ${my_dir}/${apollo_home}/apollo-portal/scripts/startup.sh
ExecStop=/bin/bash ${my_dir}/${apollo_home}/apollo-portal/scripts/shutdown.sh
Restart=on-failure
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF
    elif [[ $1 == "config_admin" ]];then
        echo_info 生成apollo-configservice.service文件用于systemd控制
        cat >/etc/systemd/system/apollo-configservice.service <<EOF
[Unit]
Description=Apollo ConfigService, install script from https://github.com/zhegeshijiehuiyouai/RoadToDevOps
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
User=${sys_user}
Group=${sys_user}
Type=forking
ExecStart=/bin/bash ${my_dir}/${apollo_home}/apollo-configservice/scripts/startup.sh
ExecStop=/bin/bash ${my_dir}/${apollo_home}/apollo-configservice/scripts/shutdown.sh
Restart=on-failure
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF
        echo_info 生成apollo-adminservice.service文件用于systemd控制
        cat >/etc/systemd/system/apollo-adminservice.service <<EOF
[Unit]
Description=Apollo AdminService, install script from https://github.com/zhegeshijiehuiyouai/RoadToDevOps
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
User=${sys_user}
Group=${sys_user}
Type=forking
ExecStart=/bin/bash ${my_dir}/${apollo_home}/apollo-adminservice/scripts/startup.sh
ExecStop=/bin/bash ${my_dir}/${apollo_home}/apollo-adminservice/scripts/shutdown.sh
Restart=on-failure
PrivateTmp=false

[Install]
WantedBy=multi-user.target
EOF
    fi
    systemctl daemon-reload
}

function echo_summary() {
    # 目录授权最后统一做，干脆写在这里算了，反正这里都是各个install函数最后的步骤
    echo_info 目录授权
    chown -R ${sys_user}:${sys_user} ${my_dir}/${apollo_home}
    echo

    function echo_summary_portal() {
        echo_info apollo-portal已部署完毕，启动过程较耗时，请手动启动
        echo -e "\033[37m                  地址：http://${machine_ip}:${port_portal}\033[0m"
        echo -e "\033[37m                  默认账号：apollo\033[0m"
        echo -e "\033[37m                  默认密码：admin\033[0m"
        echo -e "\033[37m                  启动命令：systemctl start apollo-portal\033[0m"
    }
    function echo_summary_config_admin() {
        echo_info apollo-configservice、apollo-adminservice已部署完毕，启动过程较耗时，请手动启动
        echo -e "\033[37m                  启动命令：systemctl start apollo-configservice\033[0m"
        echo -e "\033[37m                  启动命令：systemctl start apollo-adminservice\033[0m"
    }
    if [ ${USER_INPUT_INSTALL} -eq 2 ];then
        echo_summary_portal
        echo_summary_config_admin
    elif [ ${USER_INPUT_INSTALL} -eq 3 ];then
        echo_summary_portal
    elif [ ${USER_INPUT_INSTALL} -eq 4 ];then
        echo_summary_config_admin
    fi
}

function install_portal_only() {
    check_port ${port_portal}

    echo_info portal数据库检测
    check_mysql ${config_admin_mysql_url} ${config_admin_mysql_port} ${config_admin_mysql_user} ${config_admin_mysql_pass}
    is_init_portal_mysql

    echo_info 下载apollo-portal二进制包
    echo_info 温馨提示，如果从github下载包过慢的话，可以提前下载二进制包放在${src_dir}目录后，再执行本脚本
    echo_info github地址：https://github.com/apolloconfig/apollo/releases
    download_binary_zip portal

    echo_info 配置apollo-portal
    config_apollo portal
    generate_unit_file portal

    # 既部署portal，又部署config和amdin时，在最后才显示summary，否则现在显示
    if [ ${USER_INPUT_INSTALL} -ne 2 ];then
        echo_summary
    fi
}

function install_config_admin_only() {
    check_port ${port_config} ${port_admin}
    echo_info config/admin数据库检测
    check_mysql ${portal_mysql_url} ${portal_mysql_port} ${portal_mysql_user} ${portal_mysql_pass}
    is_init_config_admin_mysql

    echo_info 下载apollo-configservice、apollo-adminservice二进制包
    echo_info 温馨提示，如果从github下载包过慢的话，可以提前下载二进制包放在${src_dir}目录后，再执行本脚本
    echo_info github地址：https://github.com/apolloconfig/apollo/releases
    download_binary_zip config_admin

    echo_info 配置config/admin
    config_apollo config_admin
    generate_unit_file config_admin

    # 既部署portal，又部署config和amdin时，在最后才显示summary，否则现在显示
    if [ ${USER_INPUT_INSTALL} -ne 2 ];then
        echo_summary
    fi
}

function install_by_binary() {
    install_config_admin_only
    install_portal_only
    echo_summary
}

function main() {
    echo
    echo "脚本支持以下部署方式"
    echo "[1] 使用docker部署一套apollo"
    echo "[2] 使用apollo二进制包部署一套apollo"
    echo "[3] 只部署apollo-portal"
    echo "[4] 只部署apollo-adminservice、apollo-configservice"
    echo
    read -p "请输入数字选择部署方式：" -e USER_INPUT_INSTALL

    preinstall
    case ${USER_INPUT_INSTALL} in
        1)
            install_by_docker
            ;;
        2)
            install_by_binary
            ;;
        3)
            install_portal_only
            ;;
        4)
            install_config_admin_only
            ;;
        *)
            echo_error 输入错误
            exit 1
    esac
}

main
