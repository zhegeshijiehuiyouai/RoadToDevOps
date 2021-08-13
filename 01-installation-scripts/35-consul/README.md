## 说明
本脚本支持部署`server`端和`client`端的`consul`

在部署`server`端时，请将第一个`server`节点设置为`leader`（根据脚本提示），其余设为`follower`  
在部署`client`端时，需要指定一个`server`的`ip`地址，可以是`server`集群中的任意一个节点`ip`