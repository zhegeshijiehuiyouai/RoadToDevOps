#!/bin/bash

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

echo_info 配置历史命令格式
cat > /etc/profile.d/init.sh << EOF
# 历史命令格式
USER_IP=\$(who -u am i 2>/dev/null| awk '{print \$NF}'|sed -e 's/[()]//g')
export HISTTIMEFORMAT="\${USER_IP} > %F %T [\$(whoami)@\$(hostname)] "
EOF


echo_warning 各系统参数已调整完毕，请执行 source /etc/profile 刷新环境变量；或者重新打开一个终端，在新终端里操作