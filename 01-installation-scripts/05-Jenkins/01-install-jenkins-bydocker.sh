#!/bin/bash

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m设置timezone\033[0m"
echo "Asia/Shanghai" > /etc/timezone
script_dir=/data/script
jenkins_out_home=/data/jenkins
[ -d $script_dir ] || mkdir -p $script_dir
[ -d $jenkins_out_home ] || mkdir -p $jenkins_out_home

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m通过docker启动jenkins中文社区版\033[0m"
# 这个是中文社区的镜像，官方镜是 jenkins/jenkins:lts
docker run -u root --name=jenkins --restart=always -d --network=host \
       -v ${jenkins_out_home}:/var/jenkins_home \
       -v ${script_dir}:/data/script \
       -v /var/run/docker.sock:/var/run/docker.sock \
       -v /etc/localtime:/etc/localtime \
       -v /etc/timezone:/etc/timezone \
       jenkinszh/jenkins-zh:lts

if [ $? -ne 0 ];then
    exit 1
fi
echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mjenkins已启动成功，以下是相关信息：\033[0m"
echo -e "\033[37m                  端口：8080\033[0m"
echo -e "\033[37m                  自定义脚本目录：${script_dir} ，该目录需要到jenkins上配置，这个目录做成了数据卷挂载，在宿主机和容器中均可访问\033[0m"
echo -e "\033[37m                  jenkins数据目录：${jenkins_out_home} ，不要删除该目录，这样重新运行该脚本，新生成的jenkins容器就可以获取之前的配置和数据\033[0m"
