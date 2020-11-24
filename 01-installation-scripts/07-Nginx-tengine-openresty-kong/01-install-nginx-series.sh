#!/bin/bash
# 可根据需要选择部署nginx、tengine、openresty、kong


# 所有需要下载的文件都下载到当前目录下的${src_dir}目录中
src_dir=00src00

##################从官网获取最新版本号##################
echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m从官网获取最新版本中\033[0m"

# 该变量用于显示下载的版本是不是最新版，如果从官网获取版本号失败，就提示是默认版本
version_nginx_hint="（官网最新版）"
version_tengine_hint="（官网最新版）"

nginx_default_version=1.19.4
# nginx的版本(从官网获取最新版)
curl_timeout=2
# 设置dns超时时间，避免没网情况下等很久
echo "options timeout:${curl_timeout} attempts:1 rotate" >> /etc/resolv.conf
nginx_version=$(curl -s  --connect-timeout ${curl_timeout} http://nginx.org/en/CHANGES | head -3 | grep nginx | awk '{print $4}')
# 接口正常，[ ! ${nginx_version} ]为1；接口失败，[ ! ${nginx_version} ]为0
if [ ! ${nginx_version} ];then
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31mnginx接口访问超时，使用默认版本：${nginx_default_version}\033[0m"
    nginx_version=${nginx_default_version}
    version_nginx_hint="（默认版本）"
fi
sed -i '$d' /etc/resolv.conf

tengine_default_version=2.3.2
# tengine的版本(从官网获取最新版)
echo "options timeout:${curl_timeout} attempts:1 rotate" >> /etc/resolv.conf
tengine_version=$(curl -s --connect-timeout 3 http://tengine.taobao.org/changelog_cn.html | awk -F'class="article-entry"' '{print $2}' | awk -F'id="Tengine' '{print $2}' | grep -oE "\".*\"" | grep -oE "title=.*" | awk -F"-" '{print $2}' | awk '{print $1}')
# 接口正常，[ ! ${tengine_version} ]为1；接口失败，[ ! ${tengine_version} ]为0
if [ ! ${tengine_version} ];then
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31mtengine接口访问超时，使用默认版本：${tengine_default_version}\033[0m"
    tengine_version=${tengine_default_version}
    version_tengine_hint="（默认版本）"
fi
sed -i '$d' /etc/resolv.conf
#######################################################

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
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m下载 $download_file_name 至 $(pwd)/\033[0m"
            # 检测是否有wget工具
            if [ ! -f /usr/bin/wget ];then
                echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m安装wget工具\033[0m"
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
                echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m下载 $download_file_name 至 $(pwd)/\033[0m"
                # 检测是否有wget工具
                if [ ! -f /usr/bin/wget ];then
                    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m安装wget工具\033[0m"
                    yum install -y wget
                fi
                wget $3
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            else
                # 进入此处，表示${src_dir}目录内有压缩包
                echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m发现压缩包$(pwd)/$download_file_name\033[0m"
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            fi
        fi
    else
        # 进入此处表示脚本所在目录有压缩包
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m发现压缩包$(pwd)/$download_file_name\033[0m"
        file_in_the_dir=$(pwd)
    fi
}


# 根据$1判断下载什么应用
function download() {
    case $1 in
        nginx)
            download_tar_gz ${src_dir} http://nginx.org/download/$2
            ;;
        tengine)
            download_tar_gz ${src_dir} https://tengine.taobao.org/download/$2
            ;;
        *)
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m你下载了个寂寞\033[0m"
            exit 3
            ;;
    esac
}

# 解压
function untar_tgz(){
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m解压 $1 中\033[0m"
    tar xf $1
    if [ $? -ne 0 ];then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m解压出错，请检查！\033[0m"
        exit 2
    fi
}

# 多核编译
function multi_core_compile(){
    assumeused=$(w | grep 'load average' | awk -F': ' '{print $2}' | awk -F'.' '{print $1}')
    cpucores=$(cat /proc/cpuinfo | grep -c processor)
    compilecore=$(($cpucores - $assumeused - 1))
    if [ $compilecore -ge 1 ];then
        make -j $compilecore && make -j $compilecore install
        if [ $? -ne 0 ];then
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m编译安装出错，请检查脚本\033[0m"
            exit 1
        fi
    else
        make && make install
        if [ $? -ne 0 ];then
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m编译安装出错，请检查脚本\033[0m"
            exit 1
        fi 
    fi
}

function add_user_and_group(){
    if id -g ${1} >/dev/null 2>&1; then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m${1}组已存在，无需创建\033[0m"
    else
        groupadd ${1}
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m创建${1}组\033[0m"
    fi
    if id -u ${1} >/dev/null 2>&1; then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m${1}用户已存在，无需创建\033[0m"
    else
        useradd -M -g ${1} -s /sbin/nologin ${1}
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m创建${1}用户\033[0m"
    fi
}

# 编译安装Nginx
function install_nginx(){
    # 用tag标识部署什么，后续脚本中调用
    tag=nginx
    # 部署目录
    installdir=/data/${tag}

    download ${tag} ${tag}-${nginx_version}.tar.gz
    cd ${file_in_the_dir}
    untar_tgz ${tag}-${nginx_version}.tar.gz

    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m安装依赖程序\033[0m"
    yum install -y gcc zlib zlib-devel openssl openssl-devel pcre pcre-devel

    add_user_and_group ${tag}
    cd ${tag}-${nginx_version}
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m配置编译参数\033[0m"
    ./configure --prefix=${installdir} --user=${tag} --group=${tag} --with-pcre --with-http_ssl_module --with-http_v2_module --with-stream --with-http_stub_status_module
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m多核编译\033[0m"
    multi_core_compile

    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m优化nginx.conf\033[0m"
    worker_connections=$(expr 65535 / $cpucores)
cat > ${installdir}/conf/nginx.conf << EOF
#user  nginx;
###########CPU核心数######################
worker_processes    auto;
#########为每个nginx进程分配CPU,利用多核心优势########
worker_cpu_affinity    auto;
########进程打开的最多文件描述符数目#########
worker_rlimit_nofile 65535;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;


events {
    worker_connections  ${worker_connections};
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  logs/access.log  main;
    server_tokens off;
#######################gzip压缩功能设置###############################
#########禁止nginx页面返回版本信息##############
    gzip on; #开启Gzip
    gzip_min_length 1k; #不压缩临界值，大于1K的才压缩，一般不用改
    gzip_buffers    4 16k; #缓冲
    gzip_http_version 1.0; #默认是HTTP/1.1，但用了反向代理的话，那么nginx和后端的upstream server之间默认是用HTTP/1.0协议通信的，为了反向代理能压缩，所以设置
    gzip_comp_level 3; #压缩级别，1-10，数字越大压缩的越好，时间也越长，看心情随便改吧
    gzip_types text/plain application/x-javascript text/css application/xml application/javascript application/x-font-woff image/jpeg image/gif image/png; ###进行压缩的文件类型.
    gzip_vary on; #跟Squid等缓存服务有关，on的话会在Header里增加"Vary: Accept-Encoding"
    gzip_disable "MSIE [1-6]\."; #IE6对Gzip不怎么友好，不给它Gzip了
#########实现文件传输性能提升###################
#    sendfile        on;  #开启gzip后，sendfile无效
#########在keepalive启用情况下提升网络性能##########
#    tcp_nopush     on;    # 已开启gzip，sendfile失效，故tcp_nopush失效
    tcp_nodelay    off;

    keepalive_timeout  30;

##############前台文件上传大小限制################
    client_max_body_size 200M;
##############在客户端停止响应之后,允许服务器关闭连接,释放socket关联的内存#############
    reset_timedout_connection on; 
##############设置客户端的响应超时时间.如果客户端停止读取数据,在这么多时间之后就释放过期的客户端连接###############
    send_timeout 10;
################分页面大小##########
    client_header_buffer_size 4k;
################缓存配置############
    open_file_cache max=65535 inactive=20s;  # 如果注释掉这句，后面的也就失效了
    open_file_cache_valid 30s;  #缓存检查频率
    open_file_cache_min_uses 2;  #缓存时间（20s）内的最少使用次数-未超过则移除
    open_file_cache_errors on;  #是否开启缓存错误信息
################请求超时时间设置################
    client_header_timeout 10; 
    client_body_timeout 10;
##################限制每个IP&每个server的并发连接数#############
#    limit_conn_zone \$binary_remote_addr zone=addr:10m;
#    limit_conn addr 20;
##########性能配置项，按照实际情况适当调整#########
    fastcgi_connect_timeout 1000;
    fastcgi_send_timeout 1000;
    fastcgi_read_timeout 1000;
##########不显示目录######### 
    autoindex off;
##########动态访问proxy缓存配置################
    # proxy_cache_path /data/nginx/cache levels=1:2 keys_zone=cache_one:10m max_size=1G inactive=1d; 
#########获取真实IP访问头######################    
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
#################反向代理配置##############
    # proxy_headers_hash_max_size 1024;
    # proxy_headers_hash_bucket_size 128;
##############开启websocket代理功能#############
    map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
    }
################使用ssi###################
    ssi on;
    ssi_silent_errors off;
    ssi_types text/shtml;


    server {
        listen       80;
        server_name  localhost;

        #charset koi8-r;

        #access_log  logs/host.access.log  main;

        location / {
            root   html;
            index  index.html index.htm;
        }

        #error_page  404              /404.html;

        # redirect server error pages to the static page /50x.html
        #
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }

        # proxy the PHP scripts to Apache listening on 127.0.0.1:80
        #
        #location ~ \.php\$ {
        #    proxy_pass   http://127.0.0.1;
        #}

        # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
        #
        #location ~ \.php\$ {
        #    root           html;
        #    fastcgi_pass   127.0.0.1:9000;
        #    fastcgi_index  index.php;
        #    fastcgi_param  SCRIPT_FILENAME  /scripts\$fastcgi_script_name;
        #    include        fastcgi_params;
        #}

        # deny access to .htaccess files, if Apache's document root
        # concurs with nginx's one
        #
        #location ~ /\.ht {
        #    deny  all;
        #}
    }


    # another virtual host using mix of IP-, name-, and port-based configuration
    #
    #server {
    #    listen       8000;
    #    listen       somename:8080;
    #    server_name  somename  alias  another.alias;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}


    # HTTPS server
    #
    #server {
    #    listen       443 ssl;
    #    server_name  localhost;

    #    ssl_certificate      cert.pem;
    #    ssl_certificate_key  cert.key;

    #    ssl_session_cache    shared:SSL:1m;
    #    ssl_session_timeout  5m;

    #    ssl_ciphers  HIGH:!aNULL:!MD5;
    #    ssl_prefer_server_ciphers  on;

    #    location / {
    #        root   html;
    #        index  index.html index.htm;
    #    }
    #}

}
EOF

    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m设置nginx配置文件语法高亮显示\033[0m"
    [ -d ~/.vim ] || mkdir -p ~/.vim
    \cp -rf contrib/vim/* ~/.vim/
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mNginx已安装在 ${installdir} ，详细信息如下：\n\033[0m"
    ${installdir}/sbin/nginx -V
    echo
}

# 编译安装tengine
function install_tengine(){
    # 用tag标识部署什么，后续脚本中调用
    tag=tengine
    # 部署目录
    installdir=/data/${tag}
    download ${tag} ${tag}-${tengine_version}.tar.gz
    cd ${file_in_the_dir}
    untar_tgz ${tag}-${tengine_version}.tar.gz

    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m安装依赖程序\033[0m"
    yum install -y gcc zlib zlib-devel openssl openssl-devel pcre pcre-devel

    add_user_and_group ${tag}
    cd ${tag}-${tengine_version}
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m配置编译参数\033[0m"
    ./configure --prefix=${installdir} --user=${tag} --group=${tag} --with-pcre --with-http_ssl_module --with-http_v2_module --with-stream --with-http_stub_status_module
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m多核编译\033[0m"
    multi_core_compile

    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m设置tengine配置文件语法高亮显示\033[0m"
    [ -d ~/.vim ] || mkdir -p ~/.vim
    \cp -rf contrib/vim/* ~/.vim/

    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mtengine已安装在 ${installdir} ，详细信息如下：\n\033[0m"
    ${installdir}/sbin/nginx -V
    echo
}

# yum安装openresty
function install_openresty(){
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m下载openresty官方repo\033[0m"
    [ -f /etc/yum.repos.d/openresty.repo ] && rm -f /etc/yum.repos.d/openresty.repo
    wget -O /etc/yum.repos.d/openresty.repo https://openresty.org/package/centos/openresty.repo
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m通过yum安装openresty\033[0m"
    yum install -y openresty
    if [ $? -eq 0 ];then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mopenresty已安装成功，版本信息如下：\033[0m"
        openresty -v
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m查看帮助：\033[0m"
        echo -e "\033[37m                  openresty -h\033[0m"
    else
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m安装出错，请检查系统！\033[0m"
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
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m当前版本不支持\033[0m"
        exit 1
    fi

    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mdocker配置优化\033[0m"
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
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mkong已成功启动，端口信息如下：\033[0m"
    echo -e "\033[37m                  web_port：8000\033[0m"
    echo -e "\033[37m                  web_ssl_port：8443\033[0m"
    echo -e "\033[37m                  admin_port：8001 (127.0.0.1)\033[0m"
    echo -e "\033[37m                  admin_ssl_port：8444 (127.0.0.1)\033[0m"
}

function kong_with_database(){
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m启动PostgreSQL容器\033[0m"
    docker run -d --name kong-database \
               --network=kong-net \
               -p 5432:5432 \
               -e "POSTGRES_USER=kong" \
               -e "POSTGRES_DB=kong" \
               -e "POSTGRES_PASSWORD=kong" \
               postgres:9.6
    if [ $? -ne 0 ];then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m启动PostgreSQL容器失败，请检查！\033[0m"
        exit 50
    fi
    # 等上面的容器启动好
    sleep 6
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m启动临时kong容器迁移数据\033[0m"
    docker run --rm \
               --network=kong-net \
               -e "KONG_DATABASE=postgres" \
               -e "KONG_PG_HOST=kong-database" \
               -e "KONG_PG_USER=kong" \
               -e "KONG_PG_PASSWORD=kong" \
               -e "KONG_CASSANDRA_CONTACT_POINTS=kong-database" \
               kong:latest kong migrations bootstrap
    if [ $? -ne 0 ];then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m启动临时kong容器迁移数据失败，请检查！\033[0m"
        exit 51
    fi
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m启动kong容器\033[0m"
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
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m启动kong容器失败，请检查！\033[0m"
        exit 52
    fi
    kong_info
}

function kong_without_database(){
    kong_dir=/data/kong
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m检测kong专用目录 ${kong_dir}\033[0m"
    if [ -d ${kong_dir} ];then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m目录已存在，无需创建\033[0m"
    else
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m未检测到目录，创建目录\033[0m"
        mkdir -p ${kong_dir}
    fi
    [ -d ${kong_dir}/conf ] || mkdir -p ${kong_dir}/conf
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m生成配置 ${kong_dir}/conf/kong.yml\033[0m"
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
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m启动kong容器\033[0m"
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
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m启动kong容器失败，请检查！\033[0m"
        exit 53
    fi
    kong_info
}

function choose_kong(){
    read -p "请输入数字选择（如需退出请输入q）：" kong_choice
    case $kong_choice in
        1)
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m即将安装\033[36m 带PostgreSQL数据库的kong\033[0m"
            sleep 1
            kong_with_database
            ;;
        2)
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m即将安装\033[36m 不带数据库的kong\033[0m"
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
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m正在检测是否安装了docker\033[0m"
    docker -v &> /dev/null
    if [ $? -eq 0 ];then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m检测到docker已部署\033[0m"
    else
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m未检测到docker，安装docker中\033[0m"
        install_docker
    fi

    docker network list | grep -E "[[:space:]]kong-net[[:space:]]" &> /dev/null
    if [ $? -ne 0 ];then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m创建kong专用的网络 kong-net\033[0m"
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
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m即将安装 \033[36mnginx\033[0m"
            # 等待1秒，给用户手动取消的时间
            sleep 1
            install_nginx
            ;;
        2)
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m即将安装 \033[36mtengine\033[0m"
            sleep 1
            install_tengine
            ;;
        3)
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m即将安装 \033[36mopenresty\033[0m"
            sleep 1
            install_openresty
            ;;
        4)
            echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m即将安装 \033[36mkong\033[0m"
            sleep 1
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

echo -e "\033[32m本脚本支持一键部署：\033[0m"
echo -e "\033[36m[1]\033[32m nginx     - 编译安装，${nginx_version} 版本${version_nginx_hint}\033[0m"
echo -e "\033[36m[2]\033[32m tengine   - 编译安装，${tengine_version} 版本${version_tengine_hint}\033[0m"
echo -e "\033[36m[3]\033[32m openresty - yum安装，官方repo仓库最新版\033[0m"
echo -e "\033[36m[4]\033[32m kong      - docker安装，官方docker仓库最新版\033[0m"
install_main_func