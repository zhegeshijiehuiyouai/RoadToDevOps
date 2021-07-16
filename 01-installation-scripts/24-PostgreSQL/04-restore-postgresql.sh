#!/bin/bash
# 将此脚本和所有增量备份文件（备份文件不要再放在目录里）放在同一目录下执行

PG_HOME=/data/postgresql-11
BASE_BACK_FILE=base.tar.gz
INCRE_BACK_FILE=pg_wal.tar.gz
SYSTEM_UNIT_FILE=postgresql-11.service
NOW_TIME=$(date +%F_%H_%M_%S)

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

function check_pg_running() {
    ps -ef | grep postgresql-11 | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_warning 检测到postgresql运行中，是否停止postgresql，并继续恢复 [ y/n ]
        read C_OR_NOT
        case ${C_OR_NOT} in
            y|Y)
                echo_info 停止postgresql
                systemctl stop ${SYSTEM_UNIT_FILE}
                ;;
            n|N)
                echo_info 用户中止操作
                exit 0
        esac
    fi
}

function decompression_pg_backup() {
    PG_BASE_BACK_SIZE=$(du -h ${BASE_BACK_FILE} | awk '{print $1}')
    echo_info 解压基础备份包（${PG_BASE_BACK_SIZE}），请耐心等待
    [ -d data ] || mkdir data
    tar xf ${BASE_BACK_FILE} -C data
    echo_info 解压增量备份包
    tar xf ${INCRE_BACK_FILE}
    echo_info 移动增量备份文件至pg_wal目录
    \cp -rf 0000* data/pg_wal/
}

function check_time_format() {
    echo_info 请输入要恢复的时间点（${BACK_TIME_MIN}至${BACK_TIME_MAX}之间），输入格式示例 2021-06-29 10:29:06
    read RESTORE_TIME
    if [[ ! ${RESTORE_TIME} =~ ^2[0-9]{3}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]];then
        echo_error 输入格式错误，请重新输入
        check_time_format
    fi
}

function get_restore_time_range() {
    cd ${PG_HOME}/data
    BACK_TIME_MIN=$(ls -l --full-time -t pg_wal/0* | tail -1 | awk '{print $6" "$7}' | awk -F '.' '{print $1}')
    BACK_TIME_MAX=$(ls -l --full-time -t -r pg_wal/0* | tail -1 | awk '{print $6" "$7}' | awk -F '.' '{print $1}')
    check_time_format
    echo_info 生成recovery.conf
    cat > ${PG_HOME}/data/recovery.conf << EOF
restore_command = ''
recovery_target_time = '${RESTORE_TIME}'
EOF
}

function restore_pg() {
    if [ -d ${PG_HOME}/data ];then
        echo_info 重命名原data目录：${PG_HOME}/data --\> ${PG_HOME}/data_${NOW_TIME}  # \>转义重定向符号
        mv ${PG_HOME}/data ${PG_HOME}/data_${NOW_TIME}
    fi
    echo_info 移动解压data目录至${PG_HOME}/data
    mv data ${PG_HOME}/data
    chown -R postgres:postgres ${PG_HOME}/data
    chmod 700 ${PG_HOME}/data
    get_restore_time_range
    # 如果有从库配置，注释掉从库，否则主库不能写
    sed -i "s/^synchronous_standby_names/# &/g"
    
    echo_info 启动postgresql
    systemctl start ${SYSTEM_UNIT_FILE}
}

function main() {
    check_pg_running
    decompression_pg_backup
    restore_pg
}

main