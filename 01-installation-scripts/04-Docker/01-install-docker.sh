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

echo_info 如果之前有安装docker的话，先删除docker
yum remove docker \
    docker-client \
    docker-client-latest \
    docker-ce-cli \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    docker-ce

# 检测是否有wget工具
if [ ! -f /usr/bin/wget ];then
    echo_info 安装wget工具
    yum install -y wget
fi

echo_info 使用yum安装docker
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
    echo_error 当前版本不支持
    exit 1
fi

echo_info docker配置调优
mkdir -p /etc/docker
cd /etc/docker
cat > daemon.json << EOF
{
    "registry-mirrors": ["https://bxsfpjcb.mirror.aliyuncs.com"],
    "insecure-registries":["172.21.100.16:9998"],
    "data-root": "/data/docker",
    "log-opts": {"max-size":"10m", "max-file":"1"}
}
EOF
systemctl start docker
systemctl enable docker &> /dev/null

echo_info docker已部署成功，版本信息如下：
docker -v

######## 部署docker-compose
echo_info 部署docker-compose中，请耐心等候

# curl_timeout=4
# # 设置dns超时时间，避免没网情况下等很久
# echo "options timeout:${curl_timeout} attempts:1 rotate" >> /etc/resolv.conf
# docker_compose_version=$(curl -s -H "User-Agent:Mozilla/5.0 (Macintosh; Intel Mac OS X 11_2_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.82 Safari/537.36" --connect-timeout ${curl_timeout} https://github.com/docker/compose/tags | grep "/docker/compose/releases/tag/" | head -1 | awk -F'"' '{print $2}' | xargs basename)
# # 接口正常，[ ! ${docker_compose_version} ]为1；接口失败，[ ! ${docker_compose_version} ]为0
# if [ ! ${docker_compose_version} ];then
#     echo_error docker-compose github官网[ https://github.com/docker/compose/tags ]访问超时，请检查网络！
#     sed -i '$d' /etc/resolv.conf
#     exit 10
# fi
# sed -i '$d' /etc/resolv.conf

# docker-compose v2命令和v1不一样了，故使用老版本
# docker-compose >= 1.28 需要将 .env 拷贝到 compose 目录，目前 docker 官方尚未对此问题进行定义是否属于 bug ，使用 1.27 版本，可以避免此问题
docker_compose_version=1.27.4

back_task=/tmp/.display_dot_to_show_aliviness
# 显示变化小点，表示没有卡死
cat > $back_task << EOF
function echo_warning() {
    echo -e "[\033[36m\$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m\$@\033[0m"
}
cd /usr/local/bin
while :
do
    countx=\$(ls -l | grep -E "\sdocker-compose$" | awk '{print \$1}' | grep -o x | wc -l)
    if [ 3 -ne \$countx ];then
        printf "."
        sleep 1
    else 
        exit 0
    fi

    # 如果父进程消失了，表示用户手动取消，需要退出本脚本。head -1是必须的，不然会取到多个父shell pid
    fatherpid=\$(ps -ef | grep /tmp/.display_dot_to_show_aliviness | grep -v grep | awk '{print \$3}' | head -1)
    if [ 1 -eq \$fatherpid ];then
        exit 1
    fi
done
EOF

/bin/bash $back_task &

# 使用国内源加速下载
curl -sL --connect-timeout 5 "https://get.daocloud.io/docker/compose/releases/download/${docker_compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
echo  # 换行，与小点隔开
echo_info docker-compose已部署成功，版本信息如下：
docker-compose --version

