#!/bin/bash
#
# 针对按天拆分的索引（如test-log-2020.09.21），根据日期删除es索引
# Author：zhegeshijiehuoyouai
#

# 定义 Elasticsearch 访问路径
http_es=10.0.17.98:9200
# 定义索引保留天数
keep_days=3
# 定义要删除的索引，索引之间用空格隔开
curl -w "\n" -s -XGET "http://${http_es}/_cat/indices" |awk '{print $3}' | grep -Ev "^\." >> _all_indices
for i in $(seq 1 ${keep_days});do
    dateformat=$(date -d "${i} day ago" +%Y.%m.%d)
    sed -i /${dateformat}/d _all_indices
done
wanna_del_indices=$(cat _all_indices | grep -Ev "^[[:space:]]*$")
rm -f _all_indices

# 定义关键字颜色
color=32

echo -e "\033[33m在Elasticsearch中搜索到以下索引：\033[0m"
echo ${wanna_del_indices}
echo

# 定义删除函数
clean_index(){
    curl -s -XDELETE  http://${http_es}/$1
}

# 删除操作
count=0
for index in ${wanna_del_indices}; do
    # 清理索引
    echo -e "清理 \033[${color}m${index}\033[0m 中..."
    clean_index ${index} &>/dev/null # 不显示删除的详细信息
    count=$[${count}+1]
    echo "第 ${count} 条多余索引清理完毕"
done

# 如果有清理索引，那么报告一下总情况
if [ ${count} -gt 0 ]; then
    echo ""
    echo -e "共清理 \033[${color}m${count}\033[0m 条索引\n所有多余所有均清理完毕，保留了近 \033[${color}m${keep_days}\033[0m 天的索引"
fi
