#!/bin/bash

echo -e "\033[32m如果之前有安装docker的话，先删除docker\033[0m"
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

echo -e "\033[32m安装docker\033[0m"
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
    echo "版本不支持"
    exit 1
fi

echo -e "\033[32mdocker配置调整\033[0m"
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
systemctl enable docker

echo -e "\033[32mdocker状态：\033[0m"
systemctl status docker
echo -e "\033[32mdocker版本：\033[0m"
docker -v
