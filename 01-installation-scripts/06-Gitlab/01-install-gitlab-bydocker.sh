#!/bin/bash

export GITLAB_HOME=/data/gitlab-ee-data
[ -d $GITLAB_HOME/data ] || mkdir -p $GITLAB_HOME/data
[ -d $GITLAB_HOME/logs ] || mkdir -p $GITLAB_HOME/logs
[ -d $GITLAB_HOME/config ] || mkdir -p $GITLAB_HOME/config

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m设置timezone\033[0m"
echo "Asia/Shanghai" > /etc/timezone
git_ip=$(ip a|grep inet|grep -v 127.0.0.1|grep -v inet6 | awk '{print $2}' | tr -d "addr:" | sed -n '1p' | awk -F "/" '{print$1}')

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m通过docker启动gitlab\033[0m"
docker run --detach \
       --hostname $git_ip \
       -p 443:443 -p 80:80\
       --name gitlab-ee \
       --restart always \
       -v $GITLAB_HOME/config:/etc/gitlab \
       -v $GITLAB_HOME/logs:/var/log/gitlab \
       -v $GITLAB_HOME/data:/var/opt/gitlab \
       -v /etc/localtime:/etc/localtime \
       -v /etc/timezone:/etc/timezone \
       gitlab/gitlab-ee:latest

if [ $? -ne 0 ];then
    exit 1
fi

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mgitlab已启动成功，以下是相关信息：\033[0m"
echo -e "\033[37m                  gitlab访问地址：http://${git_ip}/\033[0m"
echo -e "\033[37m                  gitlab数据目录：$(dirname ${GITLAB_HOME})/ ，不要删除该目录，这样重新运行该脚本，新生成的gitlab容器就可以获取之前的配置和数据\033[0m"