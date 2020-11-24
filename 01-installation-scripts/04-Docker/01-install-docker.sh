#!/bin/bash

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m如果之前有安装docker的话，先删除docker\033[0m"
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

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m使用yum安装docker\033[0m"
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
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m当前版本不支持\033[0m"
    exit 1
fi

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mdocker配置调优\033[0m"
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

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mdocker已部署成功，版本信息如下：\033[0m"
docker -v

######### 部署docker-compose
curl_timeout=2
# 设置dns超时时间，避免没网情况下等很久
echo "options timeout:${curl_timeout} attempts:1 rotate" >> /etc/resolv.conf
docker_compose_version=$(curl -s --connect-timeout ${curl_timeout} https://github.com/docker/compose/tags | grep "/docker/compose/releases/tag/" | head -1 | awk -F'"' '{print $2}' | xargs basename)
# 接口正常，[ ! ${docker_compose_version} ]为1；接口失败，[ ! ${docker_compose_version} ]为0
if [ ! ${docker_compose_version} ];then
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31mdocker-compose github官网[ \033[36mhttps://github.com/docker/compose/tags\033[31m ]访问超时，请检查网络！\033[0m"
    sed -i '$d' /etc/resolv.conf
    exit 10
fi
sed -i '$d' /etc/resolv.conf

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m部署docker-compose中，请耐心等候\033[0m"
# 使用国内源加速下载
curl -sL --connect-timeout 5 "https://get.daocloud.io/docker/compose/releases/download/${docker_compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mdocker-compose已部署成功，版本信息如下：\033[0m"
docker-compose --version

