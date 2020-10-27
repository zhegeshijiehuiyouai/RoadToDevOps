#!/bin/bash
# 可根据需要选择部署nginx、tengine、openresty、kong

# nginx的版本
nginx_version=1.19.3
# tengine的版本
tengine_version=2.3.2
# 所有需要下载的文件都下载到当前目录下的${src_dir}目录中
src_dir=nginx-series


# 对于要下载源码的web容器，都统一下载到一个目录里，避免文件混乱
function mkdir_and_cd(){
    # 记录当前目录，以备可能使用
    first_dir=$(pwd)
    [ -d ${src_dir} ] || mkdir ${src_dir}
    cd ${src_dir}
}

# 判断压缩包是否存在，如果不存在就下载
function download() {
    ls $2 &> /dev/null
    if [ $? -ne 0 ];then
        case $1 in
            nginx)
                echo -e "\033[32m[+] 下载${tag}源码包 $2 到 $(pwd)\033[0m"
                wget http://nginx.org/download/$2
                ;;
            tengine)
                echo -e "\033[32m[+] 下载${tag}源码包 $2 $(pwd)\033[0m"
                wget https://tengine.taobao.org/download/$2
                ;;
            *)
                echo -e "\033[31m[*] 你下载了个寂寞\033[0m"
                exit 3
                ;;
        esac
    fi
}

# 解压
function untar_tgz(){
    echo -e "\033[32m[+] 解压 $1 中\033[0m"
    tar xf $1
    if [ $? -ne 0 ];then
        echo -e "\033[31m[*] 解压出错，请检查!\033[0m"
        exit 2
    fi
}

# 多核编译
function multi_core_compile(){
    assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
    cpucores=$(cat /proc/cpuinfo | grep -c processor)
    compilecore=$(($cpucores - $assumeused - 1))
    if [ $compilecore -ge 1 ];then
        make -j $compilecore && make install
        if [ $? -ne 0 ];then
            echo -e "\n\033[31m[*] 编译安装出错，请检查脚本\033[0m\n"
            exit 1
        fi
    else
        make && make install
        if [ $? -ne 0 ];then
            echo -e "\n\033[31m[*] 编译安装出错，请检查脚本\033[0m\n"
            exit 1
        fi 
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

# 编译安装Nginx
function install_nginx(){
    mkdir_and_cd
    # 用tag标识部署什么，后续脚本中调用
    tag=nginx
    # 部署目录
    installdir=/data/${tag}

    download ${tag} ${tag}-${nginx_version}.tar.gz

    untar_tgz ${tag}-${nginx_version}.tar.gz

    echo -e "\033[32m[+] 配置编译环境\033[0m"
    yum install -y gcc zlib zlib-devel openssl openssl-devel pcre pcre-devel

    add_user_and_group ${tag}
    cd ${tag}-${nginx_version}
    ./configure --prefix=${installdir} --user=${tag} --group=${tag} --with-pcre --with-http_ssl_module --with-http_v2_module --with-stream --with-http_stub_status_module
    multi_core_compile

    echo -e "\n\n\033[33m[+] Nginx已安装在\033[0m${installdir}\033[33m，详细信息如下：\033[0m\n"
    ${installdir}/sbin/nginx -V
    echo -e "\n"
}

# 编译安装tengine
function install_tengine(){
    mkdir_and_cd
    # 用tag标识部署什么，后续脚本中调用
    tag=tengine
    # 部署目录
    installdir=/data/${tag}
    download ${tag} ${tag}-${tengine_version}.tar.gz
    untar_tgz ${tag}-${tengine_version}.tar.gz

    echo -e "\033[32m[+] 配置编译环境\033[0m"
    yum install -y gcc zlib zlib-devel openssl openssl-devel pcre pcre-devel

    add_user_and_group ${tag}
    cd ${tag}-${tengine_version}
    ./configure --prefix=${installdir} --user=${tag} --group=${tag} --with-pcre --with-http_ssl_module --with-http_v2_module --with-stream --with-http_stub_status_module
    multi_core_compile

    echo -e "\n\n\033[33m[+] tengine已安装在\033[0m${installdir}\033[33m，详细信息如下：\033[0m\n"
    ${installdir}/sbin/nginx -V
    echo -e "\n"
}

# yum安装openresty
function install_openresty(){
    echo -e "\033[32m[+] 下载openresty官方repo\033[0m"
    [ -f /etc/yum.repos.d/openresty.repo ] && rm -f /etc/yum.repos.d/openresty.repo
    wget -O /etc/yum.repos.d/openresty.repo https://openresty.org/package/centos/openresty.repo
    echo -e "\033[32m[+] yum安装openresty\033[0m"
    yum install -y openresty
    if [ $? -eq 0 ];then
        echo -e "\n\n\033[33m[+] openresty已成功，版本信息如下：\033[0m"
        openresty -v
        echo -e "\033[36m[>] 查看帮助：\033[0m"
        echo -e "\033[36m    openresty -h\033[0m"
        echo
    else
        echo -e "\033[31m[*] 安装出错，请检查系统!\033[0m"
        exit 2
    fi
}

# 安装docker
function install_docker(){
    cd /etc/yum.repos.d/
    [ -f docker-ce.repo ] || wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    yum makecache

    # 根据CentOS版本（7还是8）来进行安装
    osv=$(cat /etc/redhat-release | awk '{print $4}' | awk -F'.' '{print $1}')
    if [ $osv -eq 7 ]; then
        yum install docker-ce -y
    elif [ $osv -eq 8 ];then
        dnf install docker-ce --nobest -y
    else
        echo -e "\033[31m[*] 当前版本不支持\033[0m"
        exit 1
    fi

    echo -e "\033[36m[+] docker配置调整\033[0m"
    mkdir -p /etc/docker
    cd /etc/docker
    cat > daemon.json << EOF
{
    "registry-mirrors": ["https://bxsfpjcb.mirror.aliyuncs.com"],
    "data-root": "/data/docker",
    "log-opts": {"max-size":"10m", "max-file":"1"}
}
EOF
    systemctl start docker
    systemctl enable docker
}

function kong_info(){
    echo -e "\033[32m[>] kong已成功启动，端口信息如下：\033[0m"
    echo -e "\033[36m          web_port：8000\033[0m"
    echo -e "\033[36m      web_ssl_port：8443\033[0m"
    echo -e "\033[36m        admin_port：8001 (127.0.0.1)\033[0m"
    echo -e "\033[36m    admin_ssl_port：8444 (127.0.0.1)\033[0m"
}

function kong_with_database(){
    echo -e "\033[32m[+] 启动PostgreSQL容器\033[0m"
    docker run -d --name kong-database \
               --network=kong-net \
               -p 5432:5432 \
               -e "POSTGRES_USER=kong" \
               -e "POSTGRES_DB=kong" \
               -e "POSTGRES_PASSWORD=kong" \
               postgres:9.6
    if [ $? -ne 0 ];then
        echo -e "\033[31m[*] 启动PostgreSQL容器失败，请检查！\033[0m"
        exit 50
    fi
    # 等上面的容器启动好
    sleep 6
    echo -e "\033[32m[+] 启动临时kong容器迁移数据\033[0m"
    docker run --rm \
               --network=kong-net \
               -e "KONG_DATABASE=postgres" \
               -e "KONG_PG_HOST=kong-database" \
               -e "KONG_PG_USER=kong" \
               -e "KONG_PG_PASSWORD=kong" \
               -e "KONG_CASSANDRA_CONTACT_POINTS=kong-database" \
               kong:latest kong migrations bootstrap
    if [ $? -ne 0 ];then
        echo -e "\033[31m[*] 启动临时kong容器迁移数据失败，请检查！\033[0m"
        exit 51
    fi
    echo -e "\033[32m[+] 启动kong容器\033[0m"
    docker run -d --name kong \
               --network=kong-net \
               -e "KONG_DATABASE=postgres" \
               -e "KONG_PG_HOST=kong-database" \
               -e "KONG_PG_USER=kong" \
               -e "KONG_PG_PASSWORD=kong" \
               -e "KONG_CASSANDRA_CONTACT_POINTS=kong-database" \
               -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
               -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
               -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
               -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
               -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" \
               -p ${web_port}:8000 \
               -p ${web_ssl_port}:8443 \
               -p 127.0.0.1:${admin_port}:8001 \
               -p 127.0.0.1:${admin_ssl_port}:8444 \
               kong:latest
    if [ $? -ne 0 ];then
        echo -e "\033[31m[*] 启动kong容器失败，请检查！\033[0m"
        exit 52
    fi
    kong_info
}

function kong_without_database(){
    kong_dir=/data/kong
    echo -e "\033[32m[+] 检测kong专用目录 ${kong_dir}\033[0m"
    if [ -d ${kong_dir} ];then
        echo -e "\033[32m[#] 目录已存在，无需创建\033[0m"
    else
        echo -e "\033[32m[#] 未检测到目录，创建目录\033[0m"
        mkdir -p ${kong_dir}
    fi
    [ -d ${kong_dir}/conf ] || mkdir -p ${kong_dir}/conf
    echo -e "\033[32m[+] 生成配置 ${kong_dir}/conf/kong.yml\033[0m"
cat > ${kong_dir}/conf/kong.yml << EOF
_format_version: "2.1"
_transform: true

services:
- name: my-service
  url: https://example.com
  plugins:
  - name: key-auth
  routes:
  - name: my-route
    paths:
    - /

consumers:
- username: my-user
  keyauth_credentials:
  - key: my-key
EOF
    echo -e "\033[32m[+] 启动kong容器\033[0m"
    docker run -d --name kong \
               --network=kong-net \
               -v "${kong_dir}/conf:/usr/local/kong/declarative" \
               -e "KONG_DATABASE=off" \
               -e "KONG_DECLARATIVE_CONFIG=/usr/local/kong/declarative/kong.yml" \
               -e "KONG_PROXY_ACCESS_LOG=/dev/stdout" \
               -e "KONG_ADMIN_ACCESS_LOG=/dev/stdout" \
               -e "KONG_PROXY_ERROR_LOG=/dev/stderr" \
               -e "KONG_ADMIN_ERROR_LOG=/dev/stderr" \
               -e "KONG_ADMIN_LISTEN=0.0.0.0:8001, 0.0.0.0:8444 ssl" \
               -p ${web_port}:8000 \
               -p ${web_ssl_port}:8443 \
               -p 127.0.0.1:${admin_port}:8001 \
               -p 127.0.0.1:${admin_ssl_port}:8444 \
               kong:latest
    
    if [ $? -ne 0 ];then
        echo -e "\033[31m[*] 启动kong容器失败，请检查！\033[0m"
        exit 53
    fi
    kong_info
}

function choose_kong(){
    read -p "请输入数字选择（如需退出请输入q）：" kong_choice
    case $kong_choice in
        1)
            echo -e "\033[32m[!] 即将安装\033[36m 带PostgreSQL数据库的kong\033[32m ...\033[0m"
            sleep 1
            kong_with_database
            ;;
        2)
            echo -e "\033[32m[!] 即将安装\033[36m 不带数据库的kong\033[32m ...\033[0m"
            sleep 1
            kong_without_database
            ;;
        q|Q)
            exit 0
            ;;
        *)
            choose_kong
            ;;
    esac
}

# docker安装kong
function install_kong(){
    web_port=8000
    web_ssl_port=8443
    admin_port=8001
    admin_ssl_port=8444

    # 判断是否部署了docker
    echo -e "\033[32m[?] 判断是否安装了docker\033[0m"
    docker -v &> /dev/null
    if [ $? -eq 0 ];then
        echo -e "\033[32m[#] docker已部署\033[0m"
    else
        echo -e "\033[36m[+] 未检测到docker，安装docker中...\033[0m"
        install_docker
    fi

    docker network list | grep -E "[[:space:]]kong-net[[:space:]]" &> /dev/null
    if [ $? -ne 0 ];then
        echo -e "\033[32m\n[+] 创建kong专用的网络 kong-net\033[0m"
        docker network create kong-net
    fi

    # 选择安装带数据库的还是不带数据库的版本
    echo -e "\033[32m\n本脚本支持部署两种类型的kong：\033[0m"
    echo -e "\033[36m[1]\033[32m - 带PostgreSQL数据库的kong\033[0m"
    echo -e "\033[36m[2]\033[32m - 不带数据库的kong\033[0m"
    choose_kong
}

function install_main_func(){
    read -p "请输入数字选择要安装的组件（如需退出请输入q）：" software
    case $software in
        1)
            echo -e "\033[32m[!] 即将安装 \033[36mnginx\033[32m ...\033[0m"
            # 等待两秒，给用户手动取消的时间
            sleep 2
            install_nginx
            ;;
        2)
            echo -e "\033[32m[!] 即将安装 \033[36mtengine\033[32m ...\033[0m"
            sleep 2
            install_tengine
            ;;
        3)
            echo -e "\033[32m[!] 即将安装 \033[36mopenresty\033[32m ...\033[0m"
            sleep 2
            install_openresty
            ;;
        4)
            echo -e "\033[32m[!] 即将安装 \033[36mkong\033[32m ...\033[0m"
            sleep 2
            install_kong
            ;;
        q|Q)
            exit 0
            ;;
        *)
            install_main_func
            ;;
    esac
}

echo -e "\033[32m\n本脚本支持一键部署：\033[0m"
echo -e "\033[36m[1]\033[32m nginx     - 编译安装，${nginx_version} 版本"
echo -e "\033[36m[2]\033[32m tengine   - 编译安装，${tengine_version} 版本"
echo -e "\033[36m[3]\033[32m openresty - yum安装，官方repo仓库最新版"
echo -e "\033[36m[4]\033[32m kong      - docker安装，官方docker仓库最新版"
# 终止终端字体颜色
echo -e "\033[0m"
install_main_func