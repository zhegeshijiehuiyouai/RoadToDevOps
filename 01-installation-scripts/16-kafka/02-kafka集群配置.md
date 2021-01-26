# kafka集群配置操作
## 1、配置节点标识
以三节点集群为例，在各服务器上`kafka`目录依次执行以下命令：  
- [ kafka-1 执行 ]
```shell
sed -i 's#^broker\.id=.*#broker.id=0#g' config/server.properties
```
- [ kafka-2 执行 ]
```shell
sed -i 's#^broker\.id=.*#broker.id=1#g' config/server.properties
```
- [ kafka-3 执行 ]
```shell
sed -i 's#^broker\.id=.*#broker.id=2#g' config/server.properties
```
如果是单机部署的伪集群，那么还需要修改各个`kafka`配置文件中的`listeners`选项来修改端口，`log.dirs`选项来修改数据目录。

## 2、统一zookeeper地址
将各`kafka`连接的`zookeeper`地址配置成一样。

## 3、验证
- 在`kafka1`上创建`topic`
```shell
kafka1=192.168.1.1:9092
bin/kafka-topics.sh --create --bootstrap-server ${kafka1} --replication-factor 3 --partitions 1 --topic test-cluster-topic
```
- 在`kafka2`和`kafka3`上获取主题，如果能获取到，那么集群就建立了
```shell
kafka2=192.168.1.2:9092
kafka3=192.168.1.3:9092
bin/kafka-topics.sh --list --bootstrap-server ${kafka2}
bin/kafka-topics.sh --list --bootstrap-server ${kafka3}
```

#### 生产消息命令
```shell
kafka1=192.168.1.1:9092
bin/kafka-console-producer.sh --bootstrap-server ${kafka1} --topic test-cluster-topic
```
#### 消费消息命令
```shell
kafka2=192.168.1.2:9092
bin/kafka-console-consumer.sh --bootstrap-server ${kafka2} --topic test-cluster-topic --from-beginning
```
