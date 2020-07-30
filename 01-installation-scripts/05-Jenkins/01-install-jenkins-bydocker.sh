echo "Asia/Shanghai" > /etc/timezone
script_dir=/data/script
jenkins_out_home=/data/jenkins
[ -d $script_dir ] || mkdir $script_dir
[ -d $jenkins_out_home ] || mkdir $jenkins_out_home
docker run -u root --name=jenkins --restart=always -d --network=host \
-v ${jenkins_out_home}:/var/jenkins_home \
-v ${script_dir}:/data/script \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /etc/localtime:/etc/localtime \
-v /etc/timezone:/etc/timezone \
jenkinszh/jenkins-zh:lts
# 这个是中文社区的镜像，官方镜像是 jenkins/jenkins:lts
# 访问端口是8080，/data/script是为了调用脚本