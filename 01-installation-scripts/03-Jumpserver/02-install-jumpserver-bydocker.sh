# 生成key和token
if [ ! "$SECRET_KEY" ]; then
  SECRET_KEY=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 50`;
  echo "SECRET_KEY=$SECRET_KEY" >> ~/.bashrc;
  echo $SECRET_KEY;
else
  echo $SECRET_KEY;
fi  
if [ ! "$BOOTSTRAP_TOKEN" ]; then
  BOOTSTRAP_TOKEN=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 16`;
  echo "BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN" >> ~/.bashrc;
  echo $BOOTSTRAP_TOKEN;
else
  echo $BOOTSTRAP_TOKEN;
fi
# docker启动命令
[ -d /data/jumpserver/data ] || mkdir -p /data/jumpserver/data
[ -d /data/jumpserver/mysql ] || mkdir -p /data/jumpserver/mysql
docker run --name jms_all -d \
  -v /data/jumpserver/data:/opt/jumpserver/data \
  -v /data/jumpserver/mysql:/var/lib/mysql \
  -p 80:80 \
  -p 2222:2222 \
  -e SECRET_KEY=$SECRET_KEY \
  -e BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN \
  --restart=always \
  jumpserver/jms_all