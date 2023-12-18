### rsync的方向
源服务器 --> 目标服务器  
- `01-start-rsyncd-service.sh` 在目标服务器执行，创建rsyncd服务端。  
- 在源服务器可配置 `inotify` 来监控变化，并同步到目标服务器。  

---
**rsync命令只会同步一次，即便是在有rsyncd的情况下**，需要实时同步的话必须配置inotify。