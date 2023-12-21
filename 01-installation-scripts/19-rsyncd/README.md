### 数据同步的方向
源服务器 --> 目标服务器  
- `01-start-rsyncd-service.sh` 在`目标服务`器上执行，创建rsyncd服务端。  
- `02-start-inotifywait.sh` 在`源服务器`上执行，监控文件状态实时同步。

---
**rsync命令只会同步一次（即便是在有rsyncd的情况下）**，需要实时同步的话必须配置inotify。