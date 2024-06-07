# 1. nfs客户端调优命令
提高客户端并发，详细原理查看 [https://developer.aliyun.com/article/501417](https://developer.aliyun.com/article/501417)
```shell
#!/bin/bash
echo "options sunrpc tcp_slot_table_entries=128" >> /etc/modprobe.d/sunrpc.conf
echo "options sunrpc tcp_max_slot_table_entries=128" >>  /etc/modprobe.d/sunrpc.conf
modprobe sunrpc
sysctl -w sunrpc.tcp_slot_table_entries=128
```

# 2. nfs客户端执行`df`命令无响应处理
##  原因
NFS服务器故障或者nfs目录有变更等
## 解决方法
```shell
# 查看挂载目录
nfsstat  -m
/root/install from 10.10.8.111:/root/install
Flags: rw,vers=3,rsize=32768,wsize=32768,hard,proto=tcp,timeo=600,retrans=2,sec=sys,addr=10.10.8.111
# 卸载挂载目录
umount -lf 10.10.8.111:/root/install
```
卸载后，`df`命令即可正常执行了