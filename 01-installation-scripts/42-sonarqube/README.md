## 一、docker-compose 启动及 sonarqube 配置说明
### 1. docker-compose.yaml 语法
docker-compose.yaml 里没有 `version` 字段，是因为我是使用 `docker compose` 命令启动的，不需要该字段 
### 2. 内核参数
配置 `/etc/sysctl.conf` 建议配置不低于：
```bash
# TCP可以排队的最大连接请求数
net.core.somaxconn: 4096
# 单个进程可以拥有的虚拟内存区域的数量
vm.max_map_count: 262184
```
### 3. 因权限问题启动报错解决方法
所有的目录，会在首次启动后自动创建，但可能会因为目录权限的问题报错，解决办法：
```bash
# 在docker-compose.yaml所在的目录下执行
sudo chown -R 1000:1000 ./sonarqube*
```
### 4. 汉化
- 下载汉化jar包  
**方式1：**  
运行成功后，浏览器访问 `http://your_ip:9000`，账号密码均为 admin，在应用市场里搜索，路径： `administrator` -> `marketplace` -> 搜索 `chinese`。在跳转到的 Github 项目中下载对应版本的汉化 jar 包。  
**方式2：**  
直接访问 Github 下载对应版本的 jar 包：[https://github.com/xuhuisheng/sonar-l10n-zh](https://github.com/xuhuisheng/sonar-l10n-zh)  
- 将 jar 包上传到 `./sonarqube_extensions/downloads` （对应容器里的 `/opt/sonarqube/extensions/downloads` 目录）  
- 授权
```bash
sudo chown -R 1000:1000 ./sonarqube_extensions/downloads
```
- 重启 sonarqube，重启之后即为中文界面
```bash
docker compose restart sonarqube
```

### 5. 安装 sonarqube-community-branch-plugin 插件
因为我们部署的 sonarqube 是社区版，代码分支扫描只支持 master，要多分支支持，需要下载这个插件。
- 下载 jar 包  
项目地址：[https://github.com/mc1arke/sonarqube-community-branch-plugin](https://github.com/mc1arke/sonarqube-community-branch-plugin)  
根据 README 选择**对应版本**下载  
- 上传 jar 包、授权、重启步骤同汉化的对应步骤，请参考上面的步骤  
### 6. 将sonarqube的配置文件挂载到宿主机
以下命令在docker-compose.yaml文件同级目录下执行：
```bash
# 拷贝容器中的配置到宿主机上
mkdir -p sonarqube_conf
docker cp sonarqube:/opt/sonarqube/conf/sonar.properties ./sonarqube_conf/sonar.properties
chown -R 1000:1000 sonarqube_conf
# 关闭容器，修改docker-compose.yaml
docker compose down
vim docker-compose.yaml
# sonarqube的volumes下新增下面这行内容
- ./sonarqube_conf:/opt/sonarqube/conf
# 启动
docker compose up -d
```
## 二、使用容器 sonar-scanner 分析本地项目
### 1. 克隆项目到本地
```bash
git clone https://your-gitlab.com/group/demo.git
```
### 2. 生成令牌及分析命令
创建项目，创建令牌，选择构建技术和操作系统后，会生成分析命令，如：
```bash
sonar-scanner \
  -Dsonar.projectKey=group_demo_AZDuRhN-4PcPHzf-y35q \
  -Dsonar.sources=. \
  -Dsonar.host.url=http://172.16.20.66:9000 \
  -Dsonar.login=sqp_b4d36186f5013d50e8508f8f342aa3fc8c179b01
```
### 3. 使用容器化的 sonar-scanner 进行分析
在上面生成命令的步骤下面，会有 sonar-scanner 的使用文档，点击可跳转。9.9 长期支持版本的 sonar 对应的 sonar-scanner 文档地址 [https://docs.sonarsource.com/sonarqube/9.9/analyzing-source-code/scanners/sonarscanner/](https://docs.sonarsource.com/sonarqube/9.9/analyzing-source-code/scanners/sonarscanner/) ，根据提示选择正确的 sonar-scanner 版本。  
扫描命令：
```bash
docker run \
--rm \
-v "/data/demo:/usr/src" \
sonarsource/sonar-scanner-cli:4.8.1 \
sonar-scanner \
  -Dsonar.projectKey=group_demo_AZDuRhN-4PcPHzf-y35q \
  -Dsonar.sources=. \
  -Dsonar.host.url=http://172.16.20.66:9000 \
  -Dsonar.login=sqp_b4d36186f5013d50e8508f8f342aa3fc8c179b01
# -v 选项中的/data/demo是本地项目的目录
# sonarsource/sonar-scanner-cli:4.8.1是镜像:tag
# sonar-scanner开头的这部分就是2步骤生成的命令
```
执行完成后，sonar 上可以看到报告。
