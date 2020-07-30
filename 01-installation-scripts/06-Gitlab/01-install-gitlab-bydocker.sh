#!/bin/bash
export GITLAB_HOME=/data/gitlab-ee-data
[ -d $GITLAB_HOME/data ] || mkdir -p $GITLAB_HOME/data
[ -d $GITLAB_HOME/logs ] || mkdir -p $GITLAB_HOME/logs
[ -d $GITLAB_HOME/config ] || mkdir -p $GITLAB_HOME/config
echo "Asia/Shanghai" > /etc/timezone
git_ip=$(ip a|grep inet|grep -v 127.0.0.1|grep -v inet6 | awk '{print $2}' | tr -d "addr:" | sed -n '1p' | awk -F "/" '{print$1}')
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