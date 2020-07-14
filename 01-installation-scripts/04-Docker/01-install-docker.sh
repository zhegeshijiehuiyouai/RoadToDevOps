#!/bin/bash

echo -e "\033[32m如果之前有安装docker的话，先删除docker\033[0m"
yum remove docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    docker-ce

echo -e "\033[32m安装docker\033[0m"
cd /etc/yum.repos.d/
wget https://download.docker.com/linux/centos/docker-ce.repo
yum makecache
yum install -y docker-ce

echo -e "\033[32mdocker配置调整\033[0m"
mkdir -p /etc/docker
cd /etc/docker
cat > daemon.json << EOF
{
    "graph":"/data/docker",
    "log-opts": {"max-size":"10m", "max-file":"1"}
}
EOF
systemctl start docker
systemctl enable docker

echo -e "\033[32mdocker状态：\033[0m"
systemctl status docker
echo -e "\033[32mdocker版本：\033[0m"
docker -v
