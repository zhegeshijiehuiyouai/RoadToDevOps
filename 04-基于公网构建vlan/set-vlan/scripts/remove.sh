#!/bin/bash

# 拆除VLAN，先拆除黑名单（端口），再拆除白名单（IP）
# 由于拆除IP自带拆除端口，所以只需要这条命令
/root/BashShell/inet-based-vlan/vlan-set 2
