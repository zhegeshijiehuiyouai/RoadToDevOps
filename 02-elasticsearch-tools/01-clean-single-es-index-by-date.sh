#!/bin/bash
#
# 针对es索引是单个的情况（相较于xx.log-2019.09.28这种格式来说），根据日期删除es索引
# Author：zhegeshijiehuoyouai
# Date：2019.9.2
#

# 定义要删除的索引，索引之间用空格隔开
wanna_del_indexs="tms-devprod-new-log wms-devprod-new-log tb-devprod-new-log"
# 定义 Elasticsearch 访问路径
http_es=10.0.17.109:9200
# 定义索引保留天数
keep_days=3
# 获取所有索引
all_indexs=$(curl -s -XGET "http://${http_es}/_cat/indices" |awk '{print $3}' | uniq | sort)
# 定义关键字颜色
color=32

echo -e "\033[33m以下是您希望删除的索引：\033[0m"
echo ${wanna_del_indexs}
echo -e "\033[33m在Elasticsearch中搜索到以下索引：\033[0m"
echo ${all_indexs}
echo

# 定义删除函数
clean_index(){
cat > this_is_a_temp_file.sh << EOF
  curl -s -H'Content-Type:application/json' -d'{
      "query": {
          "range": {
              "@timestamp": {
                  "lt": "now-${keep_days}d",
                  "format": "epoch_millis"
              }
          }
      }
  }
  ' -XPOST "http://${http_es}/$1*/_delete_by_query?pretty"
EOF
sh this_is_a_temp_file.sh
rm -f this_is_a_temp_file.sh
}

# 删除操作
count=0
for index in ${wanna_del_indexs}; do
  # 判断es中是否有该索引
  echo ${all_indexs} | grep -w "${index}" &> /dev/null
  if [ $? -ne 0 ]; then
    echo -e "没有索引:\033[${color}m${index}\033[0m"
    continue
  fi

  # 清理索引
  echo -e "清理 \033[${color}m${index}\033[0m 中..."
  clean_index ${index} &> /dev/null    #不显示具体操作
  count=$[${count}+1]
  echo "第 ${count} 条多余索引清理完毕"
done

# 如果有清理索引，那么报告一下总情况
if [ ${count} -gt 0 ]; then
  echo ""
  echo -e "共清理 \033[${color}m${count}\033[0m 条索引\n所有多余所有均清理完毕，均保留了近 \033[${color}m${keep_days}\033[0m 天的索引"
fi
