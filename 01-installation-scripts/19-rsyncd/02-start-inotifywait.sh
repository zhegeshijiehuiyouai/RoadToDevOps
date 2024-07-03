#!/bin/bash

src_local=/data/00src00    # 要同步的源目录，在本机上
des_rysncd=data_00src00     # 要同步的目标rsyncd共享模块，在rsyncd上，对应一个目录
rsync_user=rsyncd      # rsyncd中定义的验证用户名
rsync_passwd_file=/etc/rsync.d/rsync.password    # 密码文件，只需要填写上面这个账户的密码
rsyncd_ip=172.16.20.66    # rsyncd的ip，同时也是目的服务器的ip
rsyncd_port=873    # rsyncd服务端的端口

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

# 脚本执行用户检测
if [[ $(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

# 检测操作系统
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
    # 阻止配置更新弹窗
    export UCF_FORCE_CONFFOLD=1
    # 阻止应用重启弹窗
    export NEEDRESTART_SUSPEND=1
elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)
else
	echo_error 不支持的操作系统
	exit 99
fi

function end_add_slash() {
    # 检测传递的值是否有“/”，有的话直接返回，没有的话在末尾添加
    my_string=$1
    if [[ $my_string != */ ]]; then
        my_string="$my_string/"
    fi
    echo $my_string
}


# 检查是否存在inofitywait命令
function check_is_exist_inotifywait() {
    if [[ $os == "centos" || $os == 'rocky' ]];then
        rc_local=/etc/rc.d/rc.local
    elif [[ $os == "ubuntu" ]];then
        rc_local=/etc/rc.local
    fi
    which inotifywait &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装inotify-tools
        if [[ $os == "centos" ]];then
            yum install -y inotify-tools
        elif [[ $os == "ubuntu" ]];then
            apt install -y inotify-tools
        fi
    fi
    # 监控时件最大数量，需调整此文件默认大小
    bf_max_queued_events=$(cat /proc/sys/fs/inotify/max_queued_events)
    if [ $bf_max_queued_events -lt 327679 ];then
        echo "fs.inotify.max_queued_events=327679" >> /etc/sysctl.conf
        sysctl -p
    fi
    # 用户实例可监控的最大目录及文件数量
    bf_max_user_watches=$(cat /proc/sys/fs/inotify/max_user_watches)
    if [ $bf_max_user_watches -lt 30000000 ];then
        echo "fs.inotify.max_user_watches=30000000" >> /etc/sysctl.conf
        sysctl -p
    fi

    # 检测是否有inotitywait进程存在
    function user_input_func() {
        read -p "请输入数字进行选择：" user_input
        case ${user_input} in
            1)
                true
                ;;
            2)
                ps -ef | grep 'inotifywait -mrq --format' | grep -v grep
                user_input_func
                ;;    
            3)
                inotifywait_pids=$(ps -ef | grep 'inotifywait -mrq --format' | grep -v grep | awk '{print $2}')
                for i in $(echo $inotifywait_pids);do
                    kill -9 $i
                done
                ;;
            4)
                inotifywait_pids=$(ps -ef | grep 'inotifywait -mrq --format' | grep -v grep | awk '{print $2}')
                for i in $(echo $inotifywait_pids);do
                    kill -9 $i
                done
                echo_warning 用户手动退出
                exit 0
                ;;
            5)
                echo_warning 用户手动退出
                exit 0
                ;;
            *)
                user_input_func
                ;;
        esac
    }

    ps -ef | grep 'inotifywait -mrq --format' | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_warning 检测到已启动的inotifywait进程
        echo_warning "[1] 忽略，继续操作"
        echo_warning "[2] 查看已启动的inotifywait进程，然后再次选择"
        echo_warning "[3] 杀死已启动的inotifywait进程，并继续操作"
        echo_warning "[4] 杀死已启动的inotifywait进程，并退出"
        echo_warning "[5] 退出"
        user_input_func
    fi
}

function launch_inotifywait() {
    # last_print_time=0 # 初始化一个变量来存储上一次打印的时间，初始值为0

    # 此方法中，这里必须要先cd到源目录，inotify再监听 ./ 才能rsync同步后目录结构一致。主要是在DELETE那块，同步上级目录才行，如果不cd到源目录，那么会将源目录本身同步到目标目录中。
    cd ${src_local}
    inotifywait -mrq --format  '%Xe %w%f' -e modify,create,delete,attrib,close_write,move ./ | while read file         # 把监控到有发生更改的"文件路径列表"循环
    do
        INO_EVENT=$(echo $file | awk '{print $1}')      # 把inotify输出切割 把事件类型部分赋值给INO_EVENT
        INO_FILE=$(echo $file | awk '{print $2}')       # 把inotify输出切割 把文件路径部分赋值给INO_FILE

        current_time=$(date +%s) # 获取当前时间的秒数
        # if [ $(($current_time - $last_print_time)) -ge 5 ]; then # 将5秒内的事件显示到同一个时间下
        #     echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>> $(date) <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<"
        #     last_print_time=$current_time
        # fi
        # echo "**** $file ****"

        #增加目录、修改、写入完成、移动进事件
        #增、改放在同一个判断，因为他们都肯定是针对文件的操作，即使是新建目录，要同步的也只是一个空目录，不会影响速度。
        #增加文件最后都会触发CLOSE_WRITEXCLOSE，所以不用管CREATE事件。
        if [[ $INO_EVENT =~ 'CREATEXISDIR' ]] || [[ $INO_EVENT =~ 'MODIFY' ]] || [[ $INO_EVENT =~ 'CLOSE_WRITE' ]] || [[ $INO_EVENT =~ 'MOVED_TO' ]];then         # 判断事件类型
            rsync -avzcR --port=${rsyncd_port} --password-file=${rsync_passwd_file} ${INO_FILE} ${rsync_user}@${rsyncd_ip}::${des_rysncd} &> /dev/null       # -c校验文件内容
        fi
        #删除、移动出事件
        if [[ $INO_EVENT =~ 'DELETE' ]] || [[ $INO_EVENT =~ 'MOVED_FROM' ]];then
            #如果直接同步已删除的路径${INO_FILE}会报no such or directory错误 所以这里同步的源是被删文件或目录的上一级路径，并加上--delete来删除目标上有而源中没有的文件，这里不能做到指定文件删除，如果删除的路径越靠近根，则同步的目录月多，同步删除的操作就越花时间。
            rsync -avzcR --port=${rsyncd_port} --delete --password-file=${rsync_passwd_file} $(dirname ${INO_FILE}) ${rsync_user}@${rsyncd_ip}::${des_rysncd} &> /dev/null
        fi
        #修改属性事件 指 touch chgrp chmod chown等操作
        if [[ $INO_EVENT =~ 'ATTRIB' ]];then
            rsync -avzcR --port=${rsyncd_port} --password-file=${rsync_passwd_file} ${INO_FILE} ${rsync_user}@${rsyncd_ip}::${des_rysncd} &> /dev/null
        fi
    done &
    echo_info "已启动对 ${src_local} 目录的监控，将实时同步到rsyncd服务器(${rsyncd_ip})的 ${des_rysncd} 共享模块"
}

function set_full_rsync_by_cornd() {
    # 为了避免有没考虑到的问题，或者在同步过程中有什么意外，添加每天一次的全量同步任务
    src_local_crontab=$(end_add_slash ${src_local})
    crontab_temp_file=crontab_$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    crontab -l > ${crontab_temp_file}
    cat ${crontab_temp_file} | grep rsync | grep $src_local &> /dev/null
    if [ $? -eq 0 ];then
        rm -f ${crontab_temp_file}
        return
    fi
    echo "12 2 * * * rsync -avz --port=${rsyncd_port} --password-file=${rsync_passwd_file} ${src_local_crontab} ${rsync_user}@${rsyncd_ip}::${des_rysncd}" >> ${crontab_temp_file}
    crontab ${crontab_temp_file}
    rm -f ${crontab_temp_file}
} 


function main() {
    check_is_exist_inotifywait
    launch_inotifywait
    set_full_rsync_by_cornd
}

main

