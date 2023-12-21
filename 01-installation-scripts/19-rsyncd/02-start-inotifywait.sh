#!/bin/bash

src_local=/data/temp    # 要同步的源目录，在本机上
des_rysncd=data_00src00     # 要同步的目标rsyncd共享模块，在rsyncd上，对应一个目录
rsync_user=icekredit      # rsyncd中定义的验证用户名
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


# 检查是否存在inofitywait命令
function check_is_exist_inotifywait() {
    which inotifywait &> /dev/null
    if [ $? -ne 0 ];then
        echo_info 安装inotify-tools
        yum install -y inotify-tools
    fi
    # 监控时件最大数量，需调整此文件默认大小
    bf_max_queued_events=$(cat /proc/sys/fs/inotify/max_queued_events)
    if [ $bf_max_queued_events -ge 327679 ];then
        af_max_queued_events=$bf_max_queued_events
    else
        af_max_queued_events=327679
    fi
    echo $af_max_queued_events > /proc/sys/fs/inotify/max_queued_events
    grep '/proc/sys/fs/inotify/max_queued_events' /etc/rc.d/rc.local &> /dev/null
    if [ $? -ne 0 ];then
        echo "echo $af_max_queued_events > /proc/sys/fs/inotify/max_queued_events" >> /etc/rc.d/rc.local
    fi
    # 用户实例可监控的最大目录及文件数量
    bf_max_user_watches=$(cat /proc/sys/fs/inotify/max_user_watches)
    if [ $bf_max_user_watches -ge 30000000 ];then
        af_max_user_watches=$bf_max_user_watches
    else
        af_max_user_watches=30000000
    fi
    echo $af_max_user_watches > /proc/sys/fs/inotify/max_user_watches
    grep '/proc/sys/fs/inotify/max_user_watches' /etc/rc.d/rc.local &> /dev/null
    if [ $? -ne 0 ];then
        echo "echo $af_max_user_watches > /proc/sys/fs/inotify/max_user_watches" >> /etc/rc.d/rc.local
    fi
}

function launch_inotifywait() {
    # last_print_time=0 # 初始化一个变量来存储上一次打印的时间，初始值为0

    # 此方法中，由于rsync同步的特性，这里必须要先cd到源目录，inotify再监听 ./ 才能rsync同步后目录结构一致。主要是在DELETE那块，同步上级目录才行，如果不cd到源目录，那么会将源目录本身同步到目标目录中。
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
    done
}


function main() {
    check_is_exist_inotifywait
    launch_inotifywait
}

main

