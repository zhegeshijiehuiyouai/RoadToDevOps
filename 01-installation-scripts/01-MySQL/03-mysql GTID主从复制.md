由于配置简单，但如果要由脚本实现，代码量太大，且配置项较多，故以文本内容进行说明
# mysql GTID主从配置操作
## 1、mysql主服务器/etc/my.cnf修改，新增内容
```shell
cat >> /etc/my.cnf <<EOF
server-id = 1
binlog_format = row
expire_logs_days = 30
max_binlog_size  = 100M
gtid_mode = ON
enforce_gtid_consistency = ON
master-verify-checksum = 1
log-bin = mysql-bin
EOF
```

## 2、重启主服务器mysql
```shell
systemctl restart mysql
```

## 3、主服务器添加同步用户
```SQL
grant replication slave on *.* to 'repl'@'172.20.222.%' identified by 'Re3#_pp111';
show master status;
```

## 4、mysql从服务器/etc/my.cnf修改，注意server-id要和主服务器不一样
```shell
cat >> /etc/my.cnf <<EOF
server-id = 2
gtid_mode = ON
enforce_gtid_consistency = ON
log-bin = mysql-bin
log-slave-updates = ON
expire_logs_days = 30
max_binlog_size  = 100M
master_info_repository=TABLE
relay_log_info_repository=TABLE
skip_slave_start=1  # 从服务器崩溃之后，重新启动，不会自动复制。崩溃后启动复制，可能数据不一致
EOF
```

## 5、重启从没服务器mysql
```shell
systemctl restart mysql
```

## 6、从服务器配置master信息
```SQL
CHANGE MASTER TO MASTER_HOST='172.20.222.43',MASTER_USER='repl',MASTER_PASSWORD='Re3#_pp111',MASTER_AUTO_POSITION=1;
start slave;
show slave status\G
```