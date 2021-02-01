# RabbitMQ集群配置步骤
***以下操作，在各节点`rabbitmq`都启动的情况下进行***
</br>
## 1、在主节点上获取主节点的`.erlang.cookie`值
选一台服务器作为主节点，查看其值
```shell
# 如果用本项目脚本部署的，那么 .erlang.cookie 在脚本配置的 rabbitmq_home 变量指定的目录下面。
# 如果通过其他方式部署的，文件应该是
# /var/lib/rabbitmq/.erlang.cookie 或者 ~/.erlang.cookie

cat /data/rabbitmq/.erlang.cookie
```


## 2、在所有节点上配置`/etc/hosts`
```shell
# rabbitmq节点间基于主机名进行通信，故各节点名应唯一，而后将集群节点都加入进集群节点 hosts 文件
192.168.1.57    node-1
192.168.1.81    node-2
192.168.1.60    node-3
```
## 3、在各子节点上操作，加入集群
**1）将主节点的 `.erlang.cookie` 的值写入到子节点的  `.erlang.cookie` 中**
```shell
vim /data/rabbitmq/.erlang.cookie
# 修改值，保存时可能会提示只读，使用 :wq! 保存即可。
# 如果上述操作不可能，那么修改该文件的权限，
# chmod 777 /data/rabbitmq/.erlang.cookie
# 修改完后，再降低文件权限，否则启动不了
# chmod 400 /data/rabbitmq/.erlang.cookie
```

**2）加入集群**
```shell
# 下面的命令可以指定节点名
# rabbitmqctl -n rabbit2 stop_app

rabbitmqctl stop_app
rabbitmqctl reset
rabbitmqctl join_cluster rabbit@node-1
rabbitmqctl start_app
```
## 4、在任一节点查看集群状态
**1）命令查看** 
```shell
rabbitmqctl cluster_status
```
**2）管理界面查看**  
访问 `http://ip:port` 查看 `Overview` 中的 `node` 
