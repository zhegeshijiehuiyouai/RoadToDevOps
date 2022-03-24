### 用法
```
source ini.sh
readINI [配置文件路径+名称] [节点名] [键值]
```

### 示例
待读取配置
```
cat file.ini
[IP]
ip = jb51.net
[MAILLIST]
mail = admin@jb51.net
```

读取示例
```
source ini.sh
readINI file.ini IP ip
# 输出
jb51.net
```