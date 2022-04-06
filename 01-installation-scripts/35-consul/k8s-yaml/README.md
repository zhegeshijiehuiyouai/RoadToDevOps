## 说明
consul server 集群3节点，类型为`statefulset`  
consul client 类型为`daemonset`  

**目录中的文件需要根据自身情况调整部分值**
### 执行顺序
1. 创建 `storageclass` (不使用的话跳过)  
provisioner-nfs-dev-01.yaml  
provisioner-nfs-dev-01.yaml  
2. 创建 `consul server`  
consul-server.yaml  
3. 创建 `consul client`  
consul-client.yaml