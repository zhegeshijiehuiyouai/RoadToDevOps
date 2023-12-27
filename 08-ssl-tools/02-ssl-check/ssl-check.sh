#!/bin/bash

unset LANG

domain_list=${domain_list:-$PWD/domain.list}
log=${log:-false}
verbose=${log:-false}
timeout=${timeout:-10}
timezone=${timezone:-Asia/Shanghai}

author="<mail@zhuangzhuang,ml> & zhegeshijiehuiyouai[github]"
version=v1.0.2
update=2022-04-25

usage(){
    cat <<EOF
Usage:
        $(basename $0) [OPTION] [ARG]
Options:
        -d, --domain            指定域名
        -l，--list              指定域名列表    (默认：$PWD/domain.list)
        -t, --timeout           指定超时时间    (默认：${timeout}s)
        -T, --timezone          指定时区        (默认：$timezone)
        -L, --log               生成日志文件    (路径：/var/log/$(basename $0)/)
        -V, --version           查看版本信息
        -v, --verbose           显示详细输出
        -h，--help              查看帮助
Example:
        $(basename $0) -Ld example.com
Description:
        $(basename $0): $version $update $author
        检查 SSL 证书颁发时间、到期时间
EOF
}

get_opt(){
    ARGS=$(getopt -o d:l:t:T:LvVh -l domain:,list:,timeout:,timezone:,log,version,help,verbose -n "$(basename $0)" -- "$@")
    [ $? != 0 ] && usage && exit 1
    eval set -- "${ARGS}"

    while :
    do
        case $1 in
            (-d|--domain)
                domain=$2
                shift 2
                ;;
            (-l|--list)
                domain_list=$2
                shift 2
                ;;
            (-t|--timeout)
                timeout=$2
                shift 2
                ;;
            (-T|--timezone)
                timezone=$2
                shift 2
                ;;
            (-V|--version)
                echo "$(basename $0): $version $update $author"
                exit 0
                ;;
            (-h|--help)
                usage
                exit 0
                ;;
            (-L|--log)
                log=true
                shift 1
                ;;
            (-v|--verbose)
                verbose=true
                shift 1
                ;;
            (--)
                if [ $# -gt 1 ]; then
                    usage
                    exit 1
                else
                    shift
                    break
                fi
                ;;
            (*)
                usage
                exit 1
        esac
    done
}

check_opt(){
    if [ -z $domain ]; then
        [ ! -f $domain_list ] && error_msg "$domain_list 域名列表不存在"
    else
        domain_list=$(mktemp $tmp_dir/domain.XXX)
        echo $domain > $domain_list
    fi

    cat $domain_list | while read domain
    do
        echo $domain | grep -v "^#" | sed "s#https\?://##" | grep -qP "^(?=^.{3,255}$)[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+(:[0-9]{1,5})*$"
        [ $? != 0 ] && error_msg "$domain 域名不合法"
    done

    echo $timeout | grep -qP "^\d{1,3}$"
    [ $? != 0 ] && error_msg "$timeout 超时时间必须是数字"
    [ $timeout -lt 0 -o $timeout -gt 1000 ] && error_msg "$timeout 超时时间范围：[0-1000]"

    if [ -n $timezone ] && which timedatectl &> /dev/null; then
        timedatectl list-timezones | grep -q "^$timezone$"
        [ $? != 0 ] && error_msg "$timezone 时区不合法"
    fi

    if [[ $log == true ]]; then
        log_dir=/var/log/$(basename $0)
        log_file=$log_dir/$(basename $0).log.$(date +"%s")
        [ ! -d $log_dir ] && mkdir -p $log_dir
        [ ! -f $log_file ] && touch $log_file
    fi
}

check_ssl(){
    for domain in $(cat $domain_list | sed "s#https\?://##")
    do
        {
            tmp=$(mktemp $tmp_dir/$domain.XXXX)

            curl https://$domain --connect-timeout $timeout -v -s -o /dev/null 2> $tmp
            
            start_time_txt=$(grep "start date" $tmp | sed "s/.*start date: //")
            expire_time_txt=$(grep "expire date" $tmp | sed "s/.*expire date: //")

            ssl_check_timestamp=$(date +"%s")
            ssl_start_timestamp=$(date --date="${start_time_txt}" +"%s")
            ssl_expire_timestamp=$(date --date="${expire_time_txt}" +"%s")

            # 查不到证书信息的情况
            if [ -z "${start_time_txt}" ];then
                if [[ $verbose == true ]]; then
                    # 输出成一行，是为了避免多个后台执行的子shell同时echo造成混淆
                    echo -e "\n检查域名: $domain\n【未检测到域名证书信息】\n"
                else
                    printf "%-44s%-40s\n" $domain "【未检测到域名证书信息】"
                fi
                # 因为在后台执行，所以可以exit
                exit 0
            fi
            
            remaining_time_second=$[($ssl_expire_timestamp-$ssl_check_timestamp)%60]
            remaining_time_minute=$[($ssl_expire_timestamp-$ssl_check_timestamp)/60%60]
            remaining_time_hour=$[($ssl_expire_timestamp-$ssl_check_timestamp)/60/60%24]
            remaining_time_day=$[($ssl_expire_timestamp-$ssl_check_timestamp)/60/60/24]
            
            issuer_name=$(grep "issuer" $tmp | sed "s/.*issuer: //")
            server_name=$(grep "subject:" $tmp | sed "s/.*CN=//" | awk -F, '{print $1}')

            # 证书过期的情况
            if [ $ssl_check_timestamp -gt $ssl_expire_timestamp ];then
                if [[ $verbose == true ]]; then
                    echo -e "\n检查域名: $domain\n通用名称: $server_name\n检查时间: $(TZ="$timezone" date -d "@$ssl_check_timestamp" +"%F %T")\n颁发时间: $(TZ="$timezone" date -d "@$ssl_start_timestamp" +"%F %T")\n到期时间: $(TZ="$timezone" date -d "@$ssl_expire_timestamp" +"%F %T")\n【已过期】${remaining_time_day}天 ${remaining_time_hour}小时${remaining_time_minute}分${remaining_time_second}秒\n颁发机构: $issuer_name\n"
                else
                    echo -e "$domain:【已过期】"
                fi
            else
                if [[ $verbose == true ]]; then
                    echo -e "\n检查域名: $domain\n通用名称: $server_name\n检查时间: $(TZ="$timezone" date -d "@$ssl_check_timestamp" +"%F %T")\n颁发时间: $(TZ="$timezone" date -d "@$ssl_start_timestamp" +"%F %T")\n到期时间: $(TZ="$timezone" date -d "@$ssl_expire_timestamp" +"%F %T")\n剩余时间: ${remaining_time_day}天 ${remaining_time_hour}小时${remaining_time_minute}分${remaining_time_second}秒\n颁发机构: $issuer_name\n"
                else
                    printf "%-44s%-40s\n" $domain "${remaining_time_day}天后到期"
                fi
            fi
        }&
    done | tee -a $log_file
    wait
}

error_msg(){
    local msg=$1
    echo -e "[\033[31;1m ERROR \033[0m] $(date +"%F %T.%5N") [ $(basename $0) ] -- $msg" && exit 1
}

check_sys(){
    if uname | grep -qi Darwin; then
        error_msg "此脚本不支持 MacOS 系统"
    fi
}

main(){
    check_sys
    tmp_dir=$PWD/$(basename $0)-tmp
    [ ! -d $tmp_dir ] && mkdir $tmp_dir
    trap "rm -rf $tmp_dir" EXIT INT
    get_opt $@
    check_opt
    check_ssl
}

main $@ && exit 0