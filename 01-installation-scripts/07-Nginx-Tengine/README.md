# Nginx热升级、手动日志切割

## 1、热升级
首先运行老的 `nginx`，`ps` 命令查看得到 `master` 进程的 `pid`，假设 `pid` 是 `999`    
### 1.1、备份老的 `nginx` 二进制文件（在 `nginx` 运行时可以执行）
``` shell
cp nginx nginx.bak
```
### 1.2、将新版本的 `nginx` 二进制文件拷贝至 `sbin` 目录
```shell
cp -f ../../nginx ./
```
### 1.3、向老 `nginx` 的 `master` 进程发送 `USR2` 信号，表示要进行热部署了；`USR2` 是用户自定义信号
```shell
kill -USR2 999
```
`nginx master` 进程会使用新复制过来的 `nginx` 二进制文件启一个新的 `nginx master` 进程。  
此时，新老 `master` 进程、`worker` 进程都在运行。不过，老的 `worker` 进程已经不再监听端口了，新的请求全部进入新的 `worker` 进程。  
新 `master` 进程的父进程是老 `master` 进程。  
### 1.4、 向老的 `master` 进程发送 `WINCH` 命令，告诉 `master` 优雅的关闭它的 `worker` 进程
```shell
kill -WINCH 999
```
此时老的 `worker` 进程会全部退出，而老的 `master` 进程不会自动退出，为了防止版本回退。
#### 1.5.1、回滚旧版本（如果需要），向旧 `Nginx` 主进程发送 `HUP` 信号，它会重新启动 `worker` 进程。同时对新 `master` 进程发送 `QUIT` 信号
```shell
kill -HUP 999
# 发送SIGHUP信号等效于 nginx -s reload （PID 999的那个nginx）
kill -QUIT newPID
```
#### 1.5.2、确定新版本没有问题，直接杀死老 `master` 进程即可，新 `master` 进程的父进程会变成 `PID` 1
```shell
kill -9 新进程ID
```
# 2、手动日志切割
清空日志重新写入。  
## 2.1、先备份之前的日志
```shell
cp access.log access.log.bak
```
## 2.2、向nginx发送reopen命令
```shell
nginx -s reopen
```
`access.log` 就会重新清空并开始写入日志。  
使用 `USR1` 命令也是同样的功能。  
```shell
kill -USR1 999
```