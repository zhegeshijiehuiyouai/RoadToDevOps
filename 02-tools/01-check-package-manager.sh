#!/bin/bash
#判断包管理工具，可作为其他脚本的内部函数

systemPackage=""
if cat /etc/issue | grep -q -E -i "ubuntu|debian";then
    systemPackage='apt'
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat";then
    systemPackage='yum'
elif cat /proc/version | grep -q -E -i "ubuntu|debian";then
    systemPackage='apt'
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat";then
    systemPackage='yum'
else
    echo "unkonw"
fi