#!/bin/bash

unset LANG

domain_list=${domain_list:-$PWD/domain.list}
log=${log:-false}
timeout=${timeout:-10}
timezone=${timezone:-Asia/Shanghai}

author="<mail@zhuangzhuang,ml>"
version=v1.0.1
update=2021-09-10

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
        -v, --version           查看版本信息
        -h，--help              查看帮助
Example:
        $(basename $0) -Ld example.com
Description:
        $(basename $0): $version $update $author
        检查 SSL 证书颁发时间、到期时间
EOF
}

get_opt(){
    ARGS=$(getopt -o d:l:t:T:Lvh -l domain:,list:,timeout:,timezone:,log,version,help -n "$(basename $0)" -- "$@")
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
            (-v|--version)
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
        echo $domain | grep -v "^#" | sed "s#https\?://##" | grep -qP "^(?=^.{3,255}$)[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+$"
        [ $? != 0 ] && error_msg "$domain 域名不合法"
    done

    echo $timeout | grep -qP "^\d{1,3}$"
    [ $? != 0 ] && error_msg "$timeout 超时时间必须是数字"
    [ $timeout -lt 0 -o $timeout -gt 1000 ] && error_msg "$timeout 超时时间范围：[0-1000]"

    if [ -n $timezone ] && which timedatectl &> /dev/null; then
        timedatectl list-timezones | grep -q "^$timezone$"
        [ $? != 0 ] && error_msg "$timezone 时区不合法"
    fi

    if [ $log == true ]; then
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
            
            ssl_check_timestamp=$(date +"%s")
            ssl_start_timestamp=$(date --date="$(grep "start date" $tmp | sed "s/.*start date: //")" +"%s")
            ssl_expire_timestamp=$(date --date="$(grep "expire date" $tmp | sed "s/.*expire date: //")" +"%s")
            
            remaining_time_second=$[($ssl_expire_timestamp-$ssl_check_timestamp)%60]
            remaining_time_minute=$[($ssl_expire_timestamp-$ssl_check_timestamp)/60%60]
            remaining_time_hour=$[($ssl_expire_timestamp-$ssl_check_timestamp)/60/60%24]
            remaining_time_day=$[($ssl_expire_timestamp-$ssl_check_timestamp)/60/60/24]
            
            issuer_name=$(grep "issuer" $tmp | sed "s/.*issuer: //")
            server_name=$(grep "subject:" $tmp | sed "s/.*CN=//" | awk -F, '{print $1}')
            
            echo
            echo "检查域名: $domain"
            echo "通用名称: $server_name"
            echo "检查时间: $(TZ="$timezone" date -d "@$ssl_check_timestamp" +"%F %T")"
            echo "颁发时间: $(TZ="$timezone" date -d "@$ssl_start_timestamp" +"%F %T")"
            echo "到期时间: $(TZ="$timezone" date -d "@$ssl_expire_timestamp" +"%F %T")"
            echo "剩余时间: ${remaining_time_day}天 ${remaining_time_hour}小时${remaining_time_minute}分${remaining_time_second}秒"
            echo "颁发机构: $issuer_name"
            echo
        }&
    done | tee -a $log_file
    done
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