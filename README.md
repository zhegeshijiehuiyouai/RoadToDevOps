[![GitHub Stars](https://img.shields.io/github/stars/zhegeshijiehuiyouai/RoadToDevOps)](https://github.com/zhegeshijiehuiyouai/RoadToDevOps/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/zhegeshijiehuiyouai/RoadToDevOps)](https://github.com/zhegeshijiehuiyouai/RoadToDevOps/fork)

***本项目最初在 CentOS 7.9 环境下开发***  
***部分脚本适配 ubuntu 20.04 / ubuntu 22.04 / ubuntu 24.04 / AlmaLinux 9.4 / RockyLinux 9.4***  

## 🔧 脚本用法
- 本项目中的各脚本，请在 `/root/` 目录以外的任意普通目录执行，否则部分脚本无法执行成功，建议 `/data/` 目录（虽然大部分脚本在 `/root/` 目录也能执行成功）。  
- 对于需要下载包的脚本，都提供了在线和离线安装的方法。离线安装的话，只需要将脚本和下载包放在同一目录即可。  
- 如果在离线环境下部署依赖于 `yum` 等工具，需要在线下载部署的，可使用以下命令将rpm包下载到本地后离线安装。  
```shell
yum install --downloadonly --downloaddir=/data/xxxpackage/ 包名  
cd /data/xxxpackage/
rpm -Uvh ./*rpm
```
</br>

> 项目致力于实现一键部署各种常见服务，实现常用功能，且具有幂等性（多次执行效果一致）的脚本，如果发现有bug，请提 issues 🙋‍♂️

## 📚 目录结构
```shell
.
├── 01-installation-scripts
│   ├── 01-MySQL
│   ├── 02-Zabbix
│   ├── 03-Jumpserver
│   ├── 04-Docker
│   ├── 05-Jenkins
│   ├── 06-Gitlab
│   ├── 07-Nginx-tengine
│   ├── 08-Elasticsearch
│   ├── 09-Redis
│   ├── 10-GoAccess
│   ├── 11-vsftp
│   ├── 12-MongoDB
│   ├── 13-jdk
│   ├── 14-zookeeper
│   ├── 15-maven
│   ├── 16-kafka
│   ├── 17-rabbitmq
│   ├── 18-sftpgo
│   ├── 19-rsyncd
│   ├── 20-nfs
│   ├── 21-tomcat
│   ├── 22-prometheus
│   ├── 23-grafana
│   ├── 24-PostgreSQL
│   ├── 25-RocketMQ
│   ├── 26-Nexus
│   ├── 27-yapi
│   ├── 28-Node.js
│   ├── 29-code-push-server
│   ├── 30-openvpn
│   ├── 31-clickhouse
│   ├── 32-nacos
│   ├── 33-flink
│   ├── 34-apollo
│   ├── 35-consul
│   ├── 36-flexgw
│   ├── 37-wireguard
│   ├── 38-sqlite3
│   ├── 39-git
│   ├── 40-ffmpeg
│   ├── 41-pyenv
│   ├── 42-sonarqube
│   ├── 43-goenv
│   └── 44-shc
├── 02-elasticsearch-tools
│   ├── 01-clean-single-es-index-by-date.sh
│   └── 02-clean-date-format-es-index-by-date.sh
├── 03-Dockerfile
│   ├── 01-nacos
│   ├── 02-feely-sys
│   ├── 03-centos
│   ├── 04-rocksdb
│   └── 05-java
├── 04-disk-tools
│   ├── 01-Create-Swap
│   ├── 02-Create-LVM
│   ├── 03-delete-empty-dir.sh
│   └── 04-wipe-data-disk.sh
├── 05-system-tools
│   ├── 01-check-package-manager.sh
│   ├── 02-update-openssl-and-openssh.sh
│   ├── 03-init-system.sh
│   ├── 04-tcp-connection-state-counter.sh
│   ├── 05-uq.sh
│   ├── 06-update-kernel.sh
│   ├── 07-show-file-create-time.sh
│   ├── 08-update-gcc.sh
│   ├── 09-update-make.sh
│   └── 10-update-glibc.sh
├── 06-Antivirus-tools
│   └── 01-kill-miner-proc.sh
├── 07-java-tools
│   ├── 01-show-busy-java-threads.sh
│   ├── 02-show-duplicate-java-classes.py
│   └── 03-find-in-jars.sh
├── 08-ssl-tools
│   ├── 01-ssl-gen
│   └── 02-ssl-check
├── 09-parse-file
│   ├── 01-yaml
│   └── 02-ini
├── 10-pve-vmware-tools
│   └── 01-pve-to-vmware
└── README.md

```
