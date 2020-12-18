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
    "data-root": "/data/docker",
    "log-opts": {"max-size":"10m", "max-file":"1"}
}
EOF
systemctl start docker
systemctl enable docker &> /dev/null

echo_info docker已部署成功，版本信息如下：
docker -v

######### 部署docker-compose
# curl_timeout=2
# # 设置dns超时时间，避免没网情况下等很久
# echo "options timeout:${curl_timeout} attempts:1 rotate" >> /etc/resolv.conf
# docker_compose_version=$(curl -s --connect-timeout ${curl_timeout} https://github.com/docker/compose/tags | grep "/docker/compose/releases/tag/" | head -1 | awk -F'"' '{print $2}' | xargs basename)
# # 接口正常，[ ! ${docker_compose_version} ]为1；接口失败，[ ! ${docker_compose_version} ]为0
# if [ ! ${docker_compose_version} ];then
#     echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31mdocker-compose github官网[ \033[36mhttps://github.com/docker/compose/tags\033[31m ]访问超时，请检查网络！\033[0m"
#     echo_error docker-compose github官网[ https://github.com/docker/compose/tags ]访问超时，请检查网络！
#     sed -i '$d' /etc/resolv.conf
#     exit 10
# fi
# sed -i '$d' /etc/resolv.conf
# 2020.12.13测试发现，当前最新版本部署有bug，故手动指定docker-compose版本
docker_compose_version=1.27.4

echo_info 部署docker-compose中，请耐心等候
# 使用国内源加速下载
curl -sL --connect-timeout 5 "https://get.daocloud.io/docker/compose/releases/download/${docker_compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
echo_info docker-compose已部署成功，版本信息如下：
docker-compose --version

