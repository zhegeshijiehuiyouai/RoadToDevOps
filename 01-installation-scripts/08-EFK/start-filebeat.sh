#!/bin/bash
[ -f /etc/timezone ] || echo "Asia/Shanghai" > /etc/timezone

function check_server_in_host() {
    server=$1
    grep ${server} /etc/hosts &> /dev/null
    if [ $? -eq 0 ];then
        echo -e "\033[33m${server} 主机信息：\033[0m"
        grep "${server}" /etc/hosts
    else
        echo -e "\033[31m/etc/hosts中未定义${server}主机\n\033[0m"
        exit
    fi
}

check_server_in_host elasticsearch
check_server_in_host kibana
echo  # 换行，美观

######################################################
log_dir=/data/myapp/tomcat/logs/catalina.out
inner_log_dir=/data/logs/catalina.log
host=`hostname`
current_dir=`pwd`
image=docker.elastic.co/beats/filebeat:7.9.1

[ -d ${current_dir}/filebeat ] || mkdir -p ${current_dir}/filebeat
if [ ! -f ${current_dir}/filebeat/filebeat.yml ];then
echo -e "\033[33m写入配置文件：${current_dir}/filebeat/filebeat.yml\033[0m"
cat > ${current_dir}/filebeat/filebeat.yml << EOF
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - ${inner_log_dir}
    multiline:
      pattern: '^[[:space:]]' # 所有的空白行，合并到前面不是空白的那行
      negate: false
      match: after
      timeout: 15s
      max_lines: 500

setup.kibana:
  host: "kibana:5601"

setup.dashboards.enabled: false
setup.ilm.enabled: false
setup.template.name: "${host}-catalina.out"       #顶格，和output对齐
setup.template.pattern: "${host}-catalina.out*"   #顶格，和output对齐
output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "${host}-catalina.out-%{+yyyy.MM.dd}" #指定index name
EOF
fi

echo -e "\033[33mdocker启动filebeat\033[0m"
echo "容器名：${host}-filebeat"
docker run \
  --network host \
  -d \
  --name ${host}-filebeat \
  --hostname ${host} \
  -v /etc/localtime:/etc/localtime \
  -v /etc/timezone:/etc/timezone \
  -v ${log_dir}:${inner_log_dir} \
  -v ${current_dir}/filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml \
  --restart always \
  ${image}
echo # 换行，美观