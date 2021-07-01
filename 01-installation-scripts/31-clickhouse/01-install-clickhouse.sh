#!/bin/bash

CLICKHOUSE_HOME=/data/clickhouse
CLICKHOUSE_TCP_PORT=9000
CLICKHOUSE_HTTP_PORT=8123
CLICKHOUSE_USER=z
CLICKHOUSE_PASSWORD=fuzaDeMima

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


function create_repo() {
    echo_info 创建clickhouse清华源repo仓库
    cat > /etc/yum.repos.d/clickhouse.repo << EOF
[repo.yandex.ru_clickhouse_rpm_stable_x86_64]
name=clickhouse stable
baseurl=https://mirrors.tuna.tsinghua.edu.cn/clickhouse/rpm/stable/x86_64
enabled=1
gpgcheck=0
EOF
}

function config_clickhouse() {
    echo_info 调整clickhouse配置
    grep "[[:space:]]+<listen_host>0.0.0.0</listen_host>" config.xml
    if [ $? -ne 0 ];then
        sed -i "/    <\!-- <listen_host>0.0.0.0<\/listen_host> -->/a \    <listen_host>0.0.0.0</listen_host>" ${CONFIG_FILE_PATH}
    fi

    sed -i "s@<http_port>.*</http_port>@<http_port>${CLICKHOUSE_HTTP_PORT}</http_port>@g" ${CONFIG_FILE_PATH}
    sed -i "s@<tcp_port>.*</tcp_port>@<tcp_port>${CLICKHOUSE_TCP_PORT}</tcp_port>@g" ${CONFIG_FILE_PATH}
    sed -i "s@<log>/var/log/clickhouse-server/clickhouse-server.log</log>@<log>${CLICKHOUSE_HOME}/logs/clickhouse-server.log</log>@g" ${CONFIG_FILE_PATH}
    sed -i "s@<path>/var/lib/clickhouse/</path>@<path>${CLICKHOUSE_HOME}/data/</path>@g" ${CONFIG_FILE_PATH}
    sed -i "s@<format_schema_path>/var/lib/clickhouse/format_schemas/</format_schema_path>@<format_schema_path>${CLICKHOUSE_HOME}/data/format_schemas/</format_schema_path>@g" ${CONFIG_FILE_PATH}
    sed -i "s@<path>/var/lib/clickhouse/access/</path>@<path>${CLICKHOUSE_HOME}/data/access/</path>@g" ${CONFIG_FILE_PATH}
    sed -i "s@<tmp_path>/var/lib/clickhouse/tmp/</tmp_path>@<tmp_path>${CLICKHOUSE_HOME}/data/tmp/</tmp_path>@g" ${CONFIG_FILE_PATH}
    sed -i "s@<user_files_path>/var/lib/clickhouse/user_files/</user_files_path>@<user_files_path>${CLICKHOUSE_HOME}/data/user_files/</user_files_path>@g" ${CONFIG_FILE_PATH}
    sed -i "s@<errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>@<errorlog>${CLICKHOUSE_HOME}/logs/clickhouse-server.err.log</errorlog>@g" ${CONFIG_FILE_PATH}

    echo_info 添加用户
    sed -i "/<users>/a\\
        <${CLICKHOUSE_USER}>\\
            <password>${CLICKHOUSE_PASSWORD}</password>\\
            <access_management>1</access_management>\\
            <networks incl="networks" replace="replace">\\
                <ip>0.0.0.0/0</ip>\\
            </networks>\\
            <profile>default</profile>\\
            <quota>default</quota>\\
        </${CLICKHOUSE_USER}>" ${USER_FILE_PATH}
    sed -i "s@<readonly>1</readonly>@<readonly>0</readonly>@g" ${USER_FILE_PATH}
}

function create_dirs() {
    mkdir -p ${CLICKHOUSE_HOME}/{data,logs}
    chown -R clickhouse:clickhouse ${CLICKHOUSE_HOME}
}

function install_by_yum() {
    echo_info 使用yum安装clickhouse
    yum install -y clickhouse-server clickhouse-client
    if [ $? -ne 0 ];then
        echo_error 安装clickhouse失败，退出
        exit 1
    fi
    CONFIG_FILE_PATH=/etc/clickhouse-server/config.xml
    USER_FILE_PATH=/etc/clickhouse-server/user.xml
}

function main() {
    create_repo
    install_by_yum
    create_dirs
    config_clickhouse
}

main