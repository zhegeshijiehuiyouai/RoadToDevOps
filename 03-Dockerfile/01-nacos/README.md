### 注：tgz包需自己下载

默认是单机模式，如果要启用集群模式，使用-e传递环境变量，如下
```shell
docker run -d --name nacos-server --hostname nacos-server -p 8082:8848 -e MODE=cluster -v /etc/nacos/conf/cluster.conf:/usr/lcoal/nacos/conf/cluster.conf nacos-server:1.1.3
```