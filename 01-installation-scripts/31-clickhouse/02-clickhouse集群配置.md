# Clickhouse集群配置
## 1、部署zookeeper集群
可参考 [这里](https://github.com/zhegeshijiehuiyouai/RoadToDevOps/tree/master/01-installation-scripts/14-zookeeper)
## 2、在各节点上分别执行以下脚本
```shell
#!/bin/bash
source /etc/profile

echo 请确认已修改本脚本中zookeeper的地址 [ y/n ]
read CONFIRM
if [ ! ${CONFIRM} == "y" ];then
    echo 用户未确认，退出
    exit 1
fi

CONFIG_FILE_PATH=/etc/clickhouse-server/config.xml
CH1=172.16.40.41
CH2=172.16.40.35
CH3=172.16.40.42
CH_TCP_PORT=9000

ZK1=172.16.40.41
ZK2=172.16.40.35
ZK3=172.16.40.42
ZK_PORT=2181

CH_CLUSTER_NAME=myclickhouse
########################################

function get_machine_ip() {
    ip a | grep -E "bond" &> /dev/null
    if [ $? -eq 0 ];then
        echo_warning 检测到绑定网卡（bond），请手动输入使用的 ip ：
        input_machine_ip_fun
    elif [ $(ip a | grep -E "inet.*e(ns|np|th).*[[:digit:]]+.*" | awk '{print $2}' | cut -d / -f 1 | wc -l) -gt 1 ];then
        echo_warning 检测到多个 ip，请手动输入使用的 ip ：
        input_machine_ip_fun
    else
        machine_ip=$(ip a | grep -E "inet.*e(ns|np|th).*[[:digit:]]+.*" | awk '{print $2}' | cut -d / -f 1)
    fi
}
get_machine_ip

echo 设置分片信息
sed -i "/<remote_servers>/a\\
        <${CH_CLUSTER_NAME}>\\
        <shard> <\!-- 定义一个分片 -->\\
            <\!-- Optional. Shard weight when writing data. Default: 1. -->\\
            <weight>1</weight>\\
            <\!-- Optional. Whether to write data to just one of the replicas. Default: false (write data to all replicas). -->\\
            <internal_replication>false</internal_replication>\\
            <replica> <\!-- 这个分片的副本存在在哪些机器上 -->\\
                <host>${CH1}</host>\\
                <port>${CH_TCP_PORT}</port>\\
            </replica>\\
            <replica>\\
                <host>${CH2}</host>\\
                <port>${CH_TCP_PORT}</port>\\
            </replica>\\
            <replica>\\
                <host>${CH3}</host>\\
                <port>${CH_TCP_PORT}</port>\\
            </replica>\\
        </shard>\\
    </${CH_CLUSTER_NAME}>" ${CONFIG_FILE_PATH}

echo 指定本机地址
sed -i "/<remote_servers>/i\\
    <macros incl=\"macros\" optional=\"true\" />\\
    <\!-- 配置分片macros变量，在用client创建表的时候回自动带入 -->\\
    <macros>\\
      <shard>1</shard>\\
      <replica>${machine_ip}</replica> <\!-- 这里指定当前集群节点的名字或者IP -->\\
    </macros>" ${CONFIG_FILE_PATH}

echo 配置zookeeper地址
sed -i "/ZooKeeper is used to store metadata about replicas/i\\
    <zookeeper incl=\"zookeeper-servers\" optional=\"true\" />\\
    <zookeeper>\\
        <node index=\"1\">\\
            <host>${ZK1}</host>\\
            <port>${ZK_PORT}</port>\\
        </node>\\
        <node index=\"2\">\\
            <host>${ZK2}</host>\\
            <port>${ZK_PORT}</port>\\
        </node>\\
        <node index=\"3\">\\
            <host>${ZK3}</host>\\
            <port>${ZK_PORT}</port>\\
        </node>\\
    </zookeeper>" ${CONFIG_FILE_PATH}

echo 重启clickhouse
systemctl restart clickhouse-server.service

```
## 3、验证
查询sql
```SQL
select * from system.clusters;
```

建表测试，在任意一台上
```shell
clickhouse-client -h 127.0.0.1 -u fuza --password fuzaDeMima --port 9000 -m
```
```SQL
CREATE TABLE t1 ON CLUSTER myclickhouse
(
    `ts` DateTime,
    `uid` String,
    `biz` String
)
ENGINE = ReplicatedMergeTree('/ClickHouse/test1/tables/{shard}/t1', '{replica}')
PARTITION BY toYYYYMMDD(ts)
ORDER BY ts
SETTINGS index_granularity = 8192
######说明 {shard}自动获取对应配置文件的macros分片设置变量 replica一样  ENGINE = ReplicatedMergeTree，不能为之前的MergeTree
######'/ClickHouse/test1/tables/{shard}/t1' 是写入zk里面的地址，唯一，注意命名规范

INSERT INTO t1 VALUES ('2019-06-07 20:01:01', 'a', 'show');
INSERT INTO t1 VALUES ('2019-06-07 20:01:02', 'b', 'show');
INSERT INTO t1 VALUES ('2019-06-07 20:01:03', 'a', 'click');
INSERT INTO t1 VALUES ('2019-06-08 20:01:04', 'c', 'show');
INSERT INTO t1 VALUES ('2019-06-08 20:01:05', 'c', 'click');
```
然后到集群的另外一台上查询
```shell
clickhouse-client -h 127.0.0.1 -u fuza --password fuzaDeMima --port 9000 -m
```
```SQL
select * from t1;
```