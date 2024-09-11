# 1、rocketmq broker
脚本默认采用`2m-2s-async`模式部署，并仅修改该模式下的配置文件。如需采用其他模式，可在`2m-2s-async`模式部署好后，手动修改`/etc/systemd/system/`目录下对应的`.service`文件，并拷贝生成的`2m-2s-async`配置至对应配置文件。

# 2、rocketmq-dashbord
源码编译条件苛刻，多个步骤需要科学上网，使用`02-install-rocketmq-dashboard.sh`编译，不一定成功，可选择使用`docker-compose`启动。  
**如果一定要使用脚本部署，需要先配置好`HTTP_PROXY`变量和`HTTPS_PROXY`变量。**  
## 2.1、docker-compose启动说明
默认开启登录认证，需要将`data`目录拷贝到`docker-compose.yaml`同级目录下才能生效。账号密码信息在`data/users.properties`文件中。  
如果希望关闭登录认证，那么删除`- ROCKETMQ_CONFIG_LOGIN_REQUIRED=true`这行，删除`volumes`配置。