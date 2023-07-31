#!/bin/bash

# 包下载目录
src_dir=$(pwd)/00src00
mysqld_exporter_port=9104
mysqld_exporter_version=0.13.0
# 部署prometheus的目录
mysqld_exporter_home=$(pwd)/mysqld_exporter-${mysqld_exporter_version}
sys_user=prometheus
unit_file_name=mysqld_exporter.service

# 要监控的mysql的信息
mysql_host=10.211.55.13
mysql_port=3306
mysql_user=root
mysql_pass=123456
# 如果要创建专用的监控账号，可使用下面的命令
# CREATE USER 'exporter'@'192.168.1.2' IDENTIFIED BY 'password';
# GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'192.168.1.2' WITH MAX_USER_CONNECTIONS 3;
# commit;
# FLUSH PRIVILEGES;
# select User,Host,authentication_string,Password from mysql.user;



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
    # 检测下载文件在服务器上是否存在
    http_code=$(curl -IsS $2 | head -1 | awk '{print $2}')
    if [ $http_code -ne 200 ];then
        echo_error $2
        echo_error 服务端文件不存在，退出
        exit 98
    fi

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

function is_run_mysqld_exporter() {
    ps -ef | grep ${mysqld_exporter_home} | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到mysqld_exporter正在运行中，退出
        exit 3
    fi

    if [ -d ${mysqld_exporter_home} ];then
        echo_error 检测到目录${mysqld_exporter_home}，请检查是否重复安装，退出
        exit 4
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

function generate_config_sample() {
    get_machine_ip

    cat > ${mysqld_exporter_home}/mysqld_exporter_prometheus.yml << EOF
# mysqld_exporter配置模板，在prometheus.yml中配置

rule_files:
  # 该rules目录为示例目录，需自己调整为实际rules目录
  - "/data/prometheus-2.25.0/rules/mysqld_exporter_rule.yml"

scrape_configs:

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'mysql'
    static_configs:
      - targets: ['${machine_ip}:${mysqld_exporter_port}']
        labels:
          instance: $(hostname)
EOF
    echo_info mysqld_exporter集成到prometheus的配置模板已生成到 ${mysqld_exporter_home}/mysqld_exporter_prometheus.yml
    
    cat > ${mysqld_exporter_home}/mysqld_exporter_rule.yml << EOF
# 在prometheus的rules目录下创建mysqld_exporter_rule.yml，并写入以下内容
# 创建的文件名，要与rule_files中的一致

groups:
- name: MySQL状态告警
  rules:
  - alert: MySQL数据库关闭告警
    expr: mysql_up == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 已关闭！"
      description: "MySQL数据库已关闭，请立刻检查！"
  - alert: 文件描述符打开过大
    expr: mysql_global_status_innodb_num_open_files > (mysql_global_variables_open_files_limit) * 0.75
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的文件描述符打开过大"
      description: "文件描述符打开过大，请考虑是否增大open_files_limit。"
  - alert: 读取缓冲区大小大于允许的最大值
    expr: mysql_global_variables_read_buffer_size > mysql_global_variables_slave_max_allowed_packet 
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的读取缓冲区大小大于允许的最大值"
      description: "读取缓冲区大小（read_buffer_size）大于最大允许数据包大小（max_allowed_packet）。这可能会中断您的复制。"
  - alert: 排序缓冲区可能配置错误
    expr: mysql_global_variables_innodb_sort_buffer_size <256*1024 or mysql_global_variables_read_buffer_size > 4*1024*1024 
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的排序缓冲区可能配置错误"
      description: "排序缓冲区过大或过小。sort_buffer_size的合适值在256k和4M之间。"
  - alert: 线程堆栈大小过小
    expr: mysql_global_variables_thread_stack <196608
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的线程堆栈大小过小"
      description: "线程堆栈大小过小，这可能会导致问题。thread_stack_size一般为256k。"
  - alert: 连接数已超过80% 
    expr: mysql_global_status_max_used_connections > mysql_global_variables_max_connections * 0.8
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的连接数已超过80%"
      description: "已使用超过最大连接限制的80％"
  - alert: InnoDB Force Recovery已启用
    expr: mysql_global_variables_innodb_force_recovery != 0 
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "MySQL数据库 {{ $labels.instance }} 的InnoDB Force Recovery已开启"
      description: "InnoDB Force Recovery已启用。此模式应仅用于数据恢复，该模式下禁止写入数据。"
  - alert: InnoDB日志文件大小过小
    expr: mysql_global_variables_innodb_log_file_size < 16777216 
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的InnoDB日志文件大小过小"
      description: "InnoDB日志文件的大小可能过小，较小的InnoDB日志文件大小可能会对性能产生影响。"
  - alert: InnoDB未在提交事务时刷新日志
    expr: mysql_global_variables_innodb_flush_log_at_trx_commit != 1
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的InnoDB未在提交事务时刷新日志"
      description: "提交事务时刷新日志事务日志的参数innodb_flush_log_at_trx_commit不为1，这可能导致断电时丢失已提交的事务。"
  - alert: 表定义缓存过小
    expr: mysql_global_status_open_table_definitions > mysql_global_variables_table_definition_cache
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的表定义缓存过小"
      description: "您的表定义缓存可能太小，这可能会对性能产生影响"
  - alert: 表打开缓存过小
    expr: mysql_global_status_open_tables >mysql_global_variables_table_open_cache * 99/100
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的表打开缓存过小"
      description: "您的表打开缓存可能太小（旧名称表缓存），这可能会对性能产生影响"
  - alert: 线程堆栈大小可能过小
    expr: mysql_global_variables_thread_stack < 262144
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的线程堆栈大小可能过小"
      description: "线程堆栈大小可能过小，这可能会导致问题。thread_stack_size一般设为256k。"
  - alert: InnoDB缓冲池实例过小
    expr: mysql_global_variables_innodb_buffer_pool_instances == 1
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的InnoDB缓冲池实例过小"
      description: "如果您使用的是MySQL 5.5及更高版本，那么出于性能原因，应使用多个InnoDB缓冲池实例。一些规则是：InnoDB缓冲池实例的大小至少应为1 GB。您可以将InnoDB缓冲池实例设置为等于计算机的内核数。"
  - alert: InnoDB插件已启用
    expr: mysql_global_variables_ignore_builtin_innodb == 1
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的InnoDB插件已启用"
      description: "InnoDB插件已启用"
  - alert: binlog日志已禁用
    expr: mysql_global_variables_log_bin != 1
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的binlog日志已禁用"
      description: "binlog日志已禁用。这将禁止您执行时间点恢复（PiTR）。"
  - alert: binlog缓存太小
    expr: mysql_global_variables_binlog_cache_size < 1048576
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的binlog缓存过小"
      description: "binlog缓存大小可能过小。建议设置为1MB或更高的值。"
  - alert: binlog statement缓存大小过小
    expr: mysql_global_variables_binlog_stmt_cache_size <1048576 and mysql_global_variables_binlog_stmt_cache_size > 0
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的binlog statement缓存大小过小"
      description: "binlog statement缓存大小可能过小。建议设置为1MB或更高的值。"
  - alert: binlog事务缓存大小过小
    expr: mysql_global_variables_binlog_cache_size  <1048576
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的binlog事务缓存大小过小"
      description: "binlog事务缓存大小可能过小。建议设置为1MB或更高的值。"
  - alert: 同步binlog已启用
    expr: mysql_global_variables_sync_binlog == 1
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的同步binlog已启用"
      description: "同步Binlog已启用。这样可以提高数据安全性，但会降低写入性能的成本。"
  - alert: IO线程已停止
    expr: mysql_slave_status_slave_io_running != 1
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的IO线程已停止"
      description: "IO线程已停止。这通常是因为它无法连接到主服务器。"
  - alert: SQL线程已停止
    expr: mysql_slave_status_slave_sql_running == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 的SQL线程已停止"
      description: "SQL线程已停止。这通常是因为它无法连接到主服务器。"
  - alert: Slave落后于Master
    expr: rate(mysql_slave_status_seconds_behind_master[1m]) >30 
    for: 1m
    labels:
      severity: warning 
    annotations:
      summary: "MySQL数据库 {{ \$labels.instance }} 落后于Master"
      description: "Slave落后于Master，请检查slave线程是否在运行，或者是否存在性能问题"
  - alert: 从库未设置为只读
    expr: mysql_global_variables_read_only != 0
    for: 1m
    labels:
      severity: page
    annotations:
      summary: "MySQL {{ \$labels.instance }} 作为从库，未设置为只读"
      description: "从库未设置为只读，这可能会导致在操作从库时，出现数据不一致的情况。"
EOF
    echo_info Prometheus针对nodes的告警规则配置模板已生成到 ${mysqld_exporter_home}/mysqld_exporter_rule.yml
}

function generate_unit_file_and_start() {
    echo_info 生成${unit_file_name}文件用于systemd控制
    cat >/usr/lib/systemd/system/${unit_file_name} <<EOF
[Unit]
Description=mysqld_exporter -- script from https://github.com/zhegeshijiehuiyouai/RoadToDevOps
Documentation=https://prometheus.io/
After=network.target

[Service]
Type=simple
User=${sys_user}
Group=${sys_user}
ExecStart=${mysqld_exporter_home}/mysqld_exporter --config.my-cnf=${mysqld_exporter_home}/my.cnf --web.listen-address=:${mysqld_exporter_port}
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    echo_info ${mysqld_exporter_home} 目录授权
    chown -R ${sys_user}:${sys_user} ${mysqld_exporter_home}
    systemctl daemon-reload
    echo_info 启动mysqld_exporter
    systemctl start ${unit_file_name}
    if [ $? -ne 0 ];then
        echo_error mysqld_exporter启动失败，请检查
        exit 1
    fi
    systemctl enable ${unit_file_name} &> /dev/null

    generate_config_sample
    chown -R ${sys_user}:${sys_user} ${mysqld_exporter_home}

    echo_info mysqld_exporter已成功部署并启动，相关信息如下：
    echo -e "\033[37m                  启动命令：systemctl start ${unit_file_name}\033[0m"
    echo -e "\033[37m                  端口：${mysqld_exporter_port}\033[0m"
    echo -e "\033[37m                  部署目录：${mysqld_exporter_home}\033[0m"
}

function config_mysql_info() {
    cat > ${mysqld_exporter_home}/my.cnf << EOF
[client]
host=${mysql_host}
port=${mysql_port}
user=${mysql_user}
password=${mysql_pass}
EOF
}

function download_and_config() {
    download_tar_gz ${src_dir} https://github.com/prometheus/mysqld_exporter/releases/download/v${mysqld_exporter_version}/mysqld_exporter-${mysqld_exporter_version}.linux-amd64.tar.gz
    cd ${file_in_the_dir}
    untar_tgz mysqld_exporter-${mysqld_exporter_version}.linux-amd64.tar.gz
    mv mysqld_exporter-${mysqld_exporter_version}.linux-amd64 ${mysqld_exporter_home}

    add_user_and_group ${sys_user}

    config_mysql_info
    generate_unit_file_and_start
}

function install_mysqld_exporter() {
    is_run_mysqld_exporter
    download_and_config
}

install_mysqld_exporter