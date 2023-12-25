### ***配置文件中所有的ip、密码均为演示或测试用的假ip、假密码，实际使用中请自行修改ip、密码***

<br/>
通过ansible批量部署zabbix客户端  
zabbix服务端是yum部署的，详见 [官网](https://www.zabbix.com/cn/download)

## 部署命令
该命令具有幂等性，可重复执行  
```shell
ansible-playbook -i hosts zabbix_agent.yml
```

## 一些说明
当前目录的 `ansible.cfg`，`hosts` 文件可以保留，这样就可以使用当前目录的配置了。  

- ansible 会优先使用执行命令当前目录的 `ansible.cfg`
- `-i` 选项可以指定 `hosts` 文件  

实测中，删除了 `/etc/ansible/{ansible.cfg,hosts}` 后，即使不使用 `-i` 指定 `host` ，ansible 也能正确的使用当前目录的 `hosts` 文件。