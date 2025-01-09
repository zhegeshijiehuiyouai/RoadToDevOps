安装 `goenv` 后，如果由于网络原因无法通过命令 `goenv install 1.22.10` 下载 `go` 二进制包的话，可以离线安装。具体步骤为：  
1. 到镜像站点 [https://golang.google.cn/dl/](https://golang.google.cn/dl/) 下载 `linux-amd64.tar.gz` 后缀的压缩包。
2. 上传文件到 `${GOENV_ROOT}/versions/` 目录
3. 执行命令
```bash
cd ${GOENV_ROOT}/versions
tar xf go1.22.10.linux-amd64.tar.gz
mv go 1.22.10
goenv versions  # 此时就可以看到1.22.10这个版本了
goenv global 1.22.10  # 设置全局版本
```