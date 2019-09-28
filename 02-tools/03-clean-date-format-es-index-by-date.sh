#!/bin/bash
#
# 针对按天拆分的索引（如test-log-2019.09.28），根据日期删除es索引
# Author：zhegeshijiehuoyouai
# Date：2019.9.28
#

# 定义 Elasticsearch 访问路径
http_es=10.0.17.98:9200
# 定义索引保留天数
keep_days=3
# 定义要删除的索引，索引之间用空格隔开
wanna_del_indexs=$(curl -H'Content-Type:application/json' -XGET "http://${http_es}/_cat/shards" |awk '{print $1}' |grep -v "\.kibana"|grep $(date -d "${keep_days} day ago" +%Y.%m.%d)|uniq)
# 获取所有索引
all_indexs=$(curl -s -H'Content-Type:application/json' -XGET "http://${http_es}/_cat/shards" | awk '{print $1}' | uniq | sort)
# 定义关键字颜色
color=32


# 定义删除函数
clean_index(){
  curl -XDELETE  http://${http_es}/$1
}

# 删除操作
count=0
for index in ${wanna_del_indexs}; do
  # 清理索引
  echo -e "清理 \033[${color}m${index}\033[0m 中..."
  clean_index ${index} &>/dev/null # 不显示删除的详细信息
  count=$[${count}+1]
  echo "第 ${count} 条多余索引清理完毕"
done

# 如果有清理索引，那么报告一下总情况
if [ ${count} -gt 0 ]; then
  echo ""
  echo -e "共清理 \033[${color}m${count}\033[0m 条索引\n所有多余所有均清理完毕，均保留了近 \033[${color}m${keep_days}\033[0m 天的索引"
fi
