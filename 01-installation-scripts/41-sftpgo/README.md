## 替换sqlite3为mysql数据库
```
vim /etc/sftpgo/sftpgo.json

  "data_provider": {
    "driver": "mysql", ##数据库类型mysql
    "name": "SFTP", ##schema名
    "host": "10.0.10.201", ##数据库IP地址
    "port": 8306, ##数据库端口号
    "username": "admin", ##用户名
    "password": "Qwer123$", ##密码
    "sslmode": 0,
    "root_cert": "",
    "client_cert": "",
```

## ssh加密套件兼容性
sftpgo默认配置禁用了一些低安全性的加密套件，部分极低版本客户端连接sftpgo出现失败
```
debug1: kex: server->client aes128-ctr hmac-sha2-256 none
debug1: kex: client->server aes128-ctr hmac-sha2-256 none
Unable to negotiate a key exchange method
```
  
排查过程中启用verbose日志，发现sftp服务端不支持客户端的加密套件。这种问题多出现在使用`centos/rhel6.x`版本的操作系统，由于很难升级操作系统，所以只能在sftpgo服务端做兼容性改造。
```
{"level":"debug","time":"2022-11-01T15:35:45.590","sender":"sftpd","message":"failed to accept an incoming connection: ssh: no common algorithm for key exchange; client offered: [diffie-hellman-group-exchange-sha256 diffie-hellman-group-exchange-sha1 diffie-hellman-group14-sha1 diffie-hellman-group1-sha1], server offered: [curve25519-sha256 curve25519-sha256@libssh.org ecdh-sha2-nistp256 ecdh-sha2-nistp384 ecdh-sha2-nistp521 diffie-hellman-group14-sha256 ext-info-s]"}
{"level":"debug","time":"2022-11-01T15:35:45.590","sender":"connection_failed","client_ip":"171.223.103.180","username":"","login_type":"no_auth_tryed","protocol":"SSH","error":"ssh: no common algorithm for key exchange; client offered: [diffie-hellman-group-exchange-sha256 diffie-hellman-group-exchange-sha1 diffie-hellman-group14-sha1 diffie-hellman-group1-sha1], server offered: [curve25519-sha256 curve25519-sha256@libssh.org ecdh-sha2-nistp256 ecdh-sha2-nistp384 ecdh-sha2-nistp521 diffie-hellman-group14-sha256 ext-info-s]"}
```

修改配置文件，重启sftpgo服务  
```
vim /etc/sftpgo/sftpgo.json

"host_key_algorithms": ["rsa-sha2-512-cert-v01@openssh.com", "rsa-sha2-256-cert-v01@openssh.com", "ssh-rsa-cert-v01@openssh.com", "ssh-dss-cert-v01@openssh.com", "ecdsa-sha2-nistp256-cert-v01@openssh.com", "ecdsa-sha2-nistp384-cert-v01@openssh.com", "ecdsa-sha2-nistp521-cert-v01@openssh.com", "ssh-ed25519-cert-v01@openssh.com", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521", "rsa-sha2-512", "rsa-sha2-256", "ssh-rsa", "ssh-dss", "ssh-ed25519"],
"kex_algorithms": ["curve25519-sha256", "curve25519-sha256@libssh.org", "ecdh-sha2-nistp256", "ecdh-sha2-nistp384", "ecdh-sha2-nistp521", "diffie-hellman-group14-sha256", "diffie-hellman-group16-sha512", "diffie-hellman-group18-sha512", "diffie-hellman-group14-sha1", "diffie-hellman-group1-sha1"],
"ciphers": [],
"macs": ["hmac-sha2-256-etm@openssh.com", "hmac-sha2-256", "hmac-sha2-512-etm@openssh.com", "hmac-sha2-512", "hmac-sha1", "hmac-sha1-96"],

systemctl restart sftpgo
```



