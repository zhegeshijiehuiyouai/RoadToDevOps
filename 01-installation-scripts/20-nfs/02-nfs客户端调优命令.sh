#!/bin/bash

# 提高客户端并发，详细原理查看 https://developer.aliyun.com/article/501417
echo "options sunrpc tcp_slot_table_entries=128" >> /etc/modprobe.d/sunrpc.conf
echo "options sunrpc tcp_max_slot_table_entries=128" >>  /etc/modprobe.d/sunrpc.conf
modprobe sunrpc
sysctl -w sunrpc.tcp_slot_table_entries=128