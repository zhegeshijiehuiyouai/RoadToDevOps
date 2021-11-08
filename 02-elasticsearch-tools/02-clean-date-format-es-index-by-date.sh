#!/bin/bash
#
# 针对按天拆分的索引（如test-log-2021-11-28），根据日期删除es索引
#

# 带格式的echo函数
function echo_info() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m$@\033[0m"
}
function echo_warning() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m$@\033[0m"
}
function echo_error() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m$@\033[0m"
}

# 定义 Elasticsearch 访问路径
HTTP_ES=10.0.17.98:9200
# 定义索引保留天数
KEEP_DAYS=3
# 定义要删除的索引，索引之间用空格隔开
curl -w "\n" -s -XGET "http://${HTTP_ES}/_cat/indices" |awk '{print $3}' | grep -Ev "^\." > _all_indices
ES_ALL_NUM_FLAG=$(cat _all_indices | grep -v "^$" | wc -l)
if [ ${ES_ALL_NUM_FLAG} -eq 0 ];then
    echo_error ES中没有索引
    rm -f _all_indices
    exit 1
fi

for i in $(seq 1 ${KEEP_DAYS});do
    dateformat=$(date -d "${i} day ago" +%Y-%m-%d)
    sed -i /${dateformat}/d _all_indices
done
WANNA_DEL_INDICES=$(cat _all_indices | grep -Ev "^[[:space:]]*$" | grep -v $(date +%Y-%m-%d))
rm -f _all_indices
ES_WANNA_DEL_NUM_FLAG=$(echo ${WANNA_DEL_INDICES} | grep -v "^$" | wc -l)
if [ ${ES_WANNA_DEL_NUM_FLAG} -eq 0 ];then
    echo_error 没有匹配的ES索引
    exit 2
fi

echo_info 在ES中搜索到以下索引：
for i in ${WANNA_DEL_INDICES};do
    echo $i
done
echo

echo_warning 是否要删除上面的索引[Y/n]：
read USER_INPUT
case ${USER_INPUT} in
    Y|y|yes)
        true
        ;;
    *)
        exit
        ;;
esac

# 定义删除函数
clean_index(){
    curl -s -XDELETE  http://${HTTP_ES}/$1
    if [ $? -ne 0 ];then
        echo_error 清理索引 $1 失败！
        exit 1
    fi
}

# 删除操作
COUNT=0
for index in ${WANNA_DEL_INDICES}; do
    # 清理索引
    echo_info 清理 ${index} 中...
    clean_index ${index} &>/dev/null # 不显示删除的详细信息
    COUNT=$[${COUNT}+1]
done

# 如果有清理索引，那么报告一下总情况
if [ ${COUNT} -gt 0 ]; then
    echo ""
    echo "-------------SUMMARY-------------"
    echo_info 共清理 ${COUNT} 条多余索引
    echo_info 所有多余所有均清理完毕，保留了近 ${KEEP_DAYS} 天的索引
fi
