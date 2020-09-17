## 部署说明 📚
本脚本部署的EFK是 `单机es+filebeat+kibana` 采集日志的模式。  
  
👏👏👏 ***kibana自带汉化哦~~~***
  
es和kibana采用docker-compose部署，部署在同一台上；  
filebeat可单独部署，也可以和`es+kibana`部署在同一台上。如果单独部署，需要在/etc/hosts中添加  
```
es+kibana的ip    kibana  elasticsearch
```
EFK部署在同一台时的目录结构
```
.
├── docker-compose.yml
├── elasticsearch
│   └── Dockerfile
├── filebeat
│   └── filebeat.yml
└── start-filebeat.sh
```
## 启动 🚀
### 1、Elasticsearch（单节点）与Kibana
使用docker-compose部署，分为带es-head和不带es-head的版本，不管选择哪一个，都需要将yml文件改为 **docker-compose.yml** ‼️  
如果不安装es-head，可以使用kibana面板中的工具管理es索引。  

启动命令：  
```
[ -f /etc/timezone ] || echo "Asia/Shanghai" > /etc/timezone
docker-compose up -d
```
### 2、Filebeat
每个节点需要部一个，为了连接到es+kibana，filebeat使用主机网络，这样最方便。启动命令会将filebeat的配置文件写入，如果生成了配置文件，那么下次启动时不会覆盖现有的配置文件，所以放心的修改吧。😄  

启动命令：  
```
./start-filebeat.sh
```