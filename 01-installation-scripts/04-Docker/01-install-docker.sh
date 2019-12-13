#!/bin/bash

yum remove docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine

# 安装docker
cd /etc/yum.repos.d/
wget https://download.docker.com/linux/centos/docker-ce.repo
yum makecache
yum install -y docker-ce

# docker配置调整
mkdir -p /etc/docker
cd /etc/docker
cat > daemon.json << EOF
{
    "graph":"/mnt/data/docker",
    "log-opts": {"max-size":"10m", "max-file":"1"}
}
EOF
systemctl start docker
systemctl enable docker
