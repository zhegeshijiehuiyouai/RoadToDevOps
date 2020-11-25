#!/bin/bash
[ -f /etc/timezone ] || echo "Asia/Shanghai" > /etc/timezone

function check_server_in_host() {
    server=$1
    grep ${server} /etc/hosts &> /dev/null
    if [ $? -eq 0 ];then
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m${server} 主机信息：\033[0m"
        grep "${server}" /etc/hosts
    else
        echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m/etc/hosts中未定义${server}主机\033[0m"
        exit
    fi
}

check_server_in_host elasticsearch
check_server_in_host kibana

######################################################
log_dir=/data/myapp/logs
inner_log_dir=/data/logs
host=`hostname`
current_dir=`pwd`
image=docker.elastic.co/beats/filebeat:7.9.1

[ -d ${current_dir}/filebeat ] || mkdir -p ${current_dir}/filebeat
if [ ! -f "${current_dir}/filebeat/filebeat.yml" ];then
echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m写入配置文件：${current_dir}/filebeat/filebeat.yml\033[0m"
cat > ${current_dir}/filebeat/filebeat.yml << EOF
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - ${inner_log_dir}/log1.log
    fields:
      type: "log1"
    multiline:
      pattern: '^[[:space:]]' # 所有的空白行，合并到前面不是空白的那行
      negate: false
      match: after
      timeout: 15s
      max_lines: 500
# 打开以下注释和output中的注释，即可配置多目录日志采集
#  - type: log
#    enabled: true
#    paths:
#      - /data/logs/log2.log
#    fields:
#      type: "log2"

setup.kibana:
  host: "kibana:5601"

setup.dashboards.enabled: false
setup.ilm.enabled: false
setup.template.name: "${host}"       #顶格，和output对齐
setup.template.pattern: "${host}-*"   #顶格，和output对齐
output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  indices:
    - index: "${host}-log1-%{+yyyy.MM.dd}" #指定index name
      when.equals:
        fields.type: "log1"
# 打开以下注释和input中的注释，即可配置多目录日志采集
#    - index: "${host}-log2-%{+yyyy.MM.dd}" #指定index name
#      when.equals:
#        fields.type: "log2"
EOF
fi

echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m通过docker启动filebeat\033[0m"
echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m容器名：${host}-filebeat\033[0m"
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

if [ $? -ne 0 ];then
    exit 1
fi
echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37mfilebeat已启动成功，以下是相关信息：\033[0m"
echo -e "\033[37m                  日志采集目录：${log_dir}\033[0m"