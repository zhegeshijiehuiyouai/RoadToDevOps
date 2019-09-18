#!/bin/bash

# 这是自定义的开机启动项
# 设置开机启动的方法：
# chmod +x /etc/rc.d/rc.local
# echo "sh /root/BashShell/start-services.sh" >> rc.local
grep "/root/BashShell/inet-based-vlan/vlan-set 1" /root/BashShell/start-services.sh
if [ $? -eq 0 ]; then
  sed -i /"\/root\/BashShell\/inet-based-vlan\/vlan-set 1"/d /root/BashShell/start-services.sh
fi

grep "/root/BashShell/inet-based-vlan/port-set 1" /root/BashShell/start-services.sh
if [ $? -eq 0 ]; then
  sed -i /"\/root\/BashShell\/inet-based-vlan\/port-set 1"/d /root/BashShell/start-services.sh
fi
