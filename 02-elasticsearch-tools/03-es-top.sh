#!/bin/bash
# 查找耗时任务对应的DSL

# ================= 核心配置区域 =================
# 默认 ES 地址
ES_HOST="127.0.0.1:9200"

# 账号密码 (如果无需密码，请保持为空字符串 "")
ES_USER=""
ES_PASS=""

# 阈值：只显示运行超过多少秒的任务
# 建议：抓写任务设 0.1，抓慢查设 1.0
THRESHOLD_SECONDS=0.1

# 显示 Top N 个最慢任务
TOP_N=5

# 采样显示的行数限制
SAMPLE_MAX_LINES=30
# ===============================================

# 1. 环境检查
if ! command -v jq &> /dev/null; then
    echo "🛑 错误: 系统未安装 'jq'。"
    exit 1
fi

# 2. 构建 curl
CURL_CMD=(curl -s --max-time 10) 
if [ -n "$ES_USER" ]; then
    CURL_CMD+=(-u "${ES_USER}:${ES_PASS}")
    echo ">> 正在连接 ES ($ES_HOST) [用户: ${ES_USER}]..."
else
    echo ">> 正在连接 ES ($ES_HOST) [无认证]..."
fi

# 3. 调用 _tasks API (移除 group_by=parents，使用默认的 nodes 结构以获取节点名)
ACTIONS="*search*,*bulk*,*index*,*update*,*write*"
# 注意：不加 group_by 默认就是 group_by=nodes，返回结构包含节点详情
URL="${ES_HOST}/_tasks?actions=${ACTIONS}&detailed=true"

echo ">> 正在抓取任务快照 (Threshold: >${THRESHOLD_SECONDS}s)..."
RESPONSE=$("${CURL_CMD[@]}" "$URL")

# 4. 校验响应
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo "🛑 错误: 无法连接到 ES。"
    exit 1
fi
if ! echo "$RESPONSE" | jq empty > /dev/null 2>&1; then
    echo "🛑 错误: ES 返回非 JSON 内容。"
    exit 1
fi

# 5. JQ 核心解析 (架构升级：Nodes -> Map Name -> Flatten)
# 逻辑：
# 1. 遍历 .nodes 字典
# 2. 提取 node.name 保存为变量
# 3. 遍历该节点下的 tasks，将 name 和 node_id 注入到 task 对象
# 4. 使用 add (即 flatten) 将所有节点的任务合并为一个大数组
# 5. 过滤 -> 排序 -> 输出
PARSED_TASKS=$(echo "$RESPONSE" | jq -r --arg threshold "$THRESHOLD_SECONDS" --arg top "$TOP_N" '
  .nodes
  | to_entries
  | map(
      .key as $nid
      | .value.name as $nname
      | .value.tasks
      | to_entries
      | map(.value + {
          task_id: .key,
          node_id: $nid,
          node_name: $nname
        })
    )
  | add
  # 判空保护：如果没有任何任务，add 结果可能为 null
  | if . == null then [] else . end
  # 过滤耗时
  | if ($threshold | tonumber) <= 0 then . else
      map(select(.running_time_in_nanos > ($threshold | tonumber * 1000000000)))
    end
  # 排序与截取
  | sort_by(.running_time_in_nanos) | reverse 
  | .[0:($top | tonumber)]
  | .[] 
  # 构造输出列：耗时 | 节点名 | 节点ID | 任务ID | 动作 | 描述
  | "\((.running_time_in_nanos / 1000000000 | tostring))\t\(.node_name)\t\(.node_id)\t\(.task_id)\t\(.action)\t\(.description)"
')

if [ -z "$PARSED_TASKS" ]; then
    if [[ "${THRESHOLD_SECONDS:-}" =~ ^0+([.]0+)?$ ]]; then
        echo ">> ✅ 当前集群空闲，无任何读写任务。"
    else
        echo ">> ✅ 当前没有发现运行时间超过 ${THRESHOLD_SECONDS} 秒的任务。"
    fi
    exit 0
fi

echo -e "\n🔥 发现以下耗时任务 (按耗时倒序):\n"

# 6. 逐行输出
IFS=$'\t'
# 输出美化：任务编号 + 分隔色（多条任务时更容易区分）
TASK_NO=0
RESET="\033[0m"
# 块底色：两种更易区分的交替色（整块统一；仅少数字段高亮）
BASE_A="\033[2;37m"  # 灰（暗）
BASE_B="\033[34m"    # 蓝（更亮，但低于高亮色）
# 高亮：耗时 / 节点名 / 索引名（三者同色）
HL="\033[22;1;33m"   # 黄（亮，显式取消 faint）
# 注意：读取变量增加了 NODE_NAME 和 NODE_ID
while read -r RUN_TIME NODE_NAME NODE_ID TASK_ID ACTION DESC; do
    TASK_NO=$((TASK_NO + 1))
    TASK_NO_PAD=$(printf "%02d" "$TASK_NO")
    case $((TASK_NO % 2)) in
        1) BASE="$BASE_A" ;;
        0) BASE="$BASE_B" ;;
    esac

    # 提取 requests 数与索引名（用于标题行展示）
    REQ_COUNT=$(echo "$DESC" | sed -n 's/.*requests\[\([^]]*\)\].*/\1/p')
    [ -z "$REQ_COUNT" ] && REQ_COUNT="-"
    TARGET_INDEX=$(echo "$DESC" | sed -n 's/.*indices\[\([^]]*\)\].*/\1/p' | awk -F, '{print $1}')
    if [ -z "$TARGET_INDEX" ]; then
        TARGET_INDEX=$(echo "$DESC" | sed -n 's/.*index\[\([^]]*\)\].*/\1/p' | awk -F, '{print $1}')
    fi

    if [ -n "$TARGET_INDEX" ]; then
        printf "%b%s%b%s%b%s%b\n" \
            "$BASE" "═══════════════════════ [ #${TASK_NO_PAD} | 索引: " \
            "$HL" "$TARGET_INDEX" \
            "$BASE" " | requests: ${REQ_COUNT} ] ═══════════════════════" \
            "$RESET"
    else
        printf "%b%s%b\n" \
            "$BASE" "═══════════════════════ [ #${TASK_NO_PAD} | 索引: - | requests: ${REQ_COUNT} ] ═══════════════════════" \
            "$RESET"
    fi
    
    if [[ "$ACTION" == *"search"* ]]; then
        TYPE_LABEL="[🔍 读/Search]"
    else
        TYPE_LABEL="[💾 写/Write]"
    fi

    printf "%b%s%b%s%b%s%b\n" "$BASE" " ⏱️  耗时: " "$HL" "${RUN_TIME}s" "$BASE" " | ${TYPE_LABEL}" "$RESET"
    printf "%b%s%b\n" "$BASE" " ⚙️  动作: ${ACTION}" "$RESET"
    printf "%b%s%b%s%b%s%b\n" "$BASE" " 🖥️  节点: " "$HL" "$NODE_NAME" "$BASE" " (${NODE_ID})" "$RESET"
    printf "%b%s%b\n" "$BASE" " 🆔  ID  : ${TASK_ID}" "$RESET"
    printf "%b%s%b\n" "$BASE" "------------------------------------------------------------" "$RESET"
    
    # 7. 侦探模式 (复用之前逻辑)
    DSL_RAW=$(echo "$DESC" | sed -n 's/.*source\[\(.*\)\]$/\1/p')

    if [ -n "$DSL_RAW" ]; then
        printf "%b%s%b\n" "$BASE" "📝 查询语句 (DSL):" "$RESET"
        DSL_PRETTY=$(echo "$DSL_RAW" | jq . 2>/dev/null)
        if [ -n "$DSL_PRETTY" ]; then
            printf "%s\n" "$DSL_PRETTY" | while IFS= read -r line; do
                printf "%b%s%b\n" "$BASE" "$line" "$RESET"
            done
        else
            printf "%b%s%b\n" "$BASE" "$DSL_RAW" "$RESET"
        fi
    else
        # 任务描述去重：标题行已包含 索引 + requests，因此移除该段的重复信息
        DESC_CLEAN=$(echo "$DESC" | sed -E 's/^requests\[[^]]*\],[[:space:]]*(indices|index)\[[^]]*\][[:space:]]*,?[[:space:]]*//')
        if [ -n "$DESC_CLEAN" ]; then
            printf "%b%s%b\n" "$BASE" "📝 任务描述:" "$RESET"
            printf "%b%s%b\n" "$BASE" "$DESC_CLEAN" "$RESET"
        fi
        
        if [ -n "$TARGET_INDEX" ] && [[ "$TARGET_INDEX" != *"*"* ]]; then
            echo ""
            printf "%b%s%b\n" \
                "$BASE" "🕵️  [侦探模式] 正在采样索引 [${TARGET_INDEX}] 的最新数据..." \
                "$RESET"
            
            SAMPLE_PAYLOAD='{"size":1, "sort":[{"_seq_no":{"order":"desc"}}]}'
            SAMPLE_RESP=$("${CURL_CMD[@]}" -H 'Content-Type: application/json' -d "$SAMPLE_PAYLOAD" "${ES_HOST}/${TARGET_INDEX}/_search" 2>/dev/null)
            
            SAMPLE_SOURCE=$(echo "$SAMPLE_RESP" | jq -r '.hits.hits[0]._source // empty')
            
            if [ -n "$SAMPLE_SOURCE" ]; then
                printf "%b%s%b\n" "$BASE" "⬇️  最新写入样本 (仅供结构参考):" "$RESET"
                echo "$SAMPLE_SOURCE" | jq . 2>/dev/null | head -n "$SAMPLE_MAX_LINES" | while IFS= read -r line; do
                    printf "%b%s%b\n" "$BASE" "$line" "$RESET"
                done
                LINE_COUNT=$(echo "$SAMPLE_SOURCE" | jq . 2>/dev/null | wc -l)
                if [ "$LINE_COUNT" -gt "$SAMPLE_MAX_LINES" ]; then
                    printf "%b%s%b\n" "$BASE" "... (数据过长，仅显示前 $SAMPLE_MAX_LINES 行)" "$RESET"
                fi
            else
                printf "%b%s%b\n" "$BASE" "⚠️  采样失败: 索引为空或无权访问。" "$RESET"
            fi
        else
            printf "%b%s%b\n" "$BASE" "⚠️  无法提取确切索引名，跳过数据采样。" "$RESET"
        fi
    fi
    printf "%b%s%b\n" "$BASE" "══════════════════════════════════════════════════════════════" "$RESET"
    echo ""

done <<< "$PARSED_TASKS"
