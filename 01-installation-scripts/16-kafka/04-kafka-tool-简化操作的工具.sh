#!/bin/bash

# ===================================================================================
# Script Configuration
# -----------------------------------------------------------------------------------
# KAFKA_HOME 和 ZK_CONNECT 将在首次运行 `init` 命令后被自动填充并持久化。
# 请勿手动修改，除非您清楚地知道自己在做什么。
# ===================================================================================
KAFKA_HOME=""
ZK_CONNECT=""

# ===================================================================================
# Global Settings
# ===================================================================================
SCRIPT_NAME=$(basename "$0")
# 显示前 Top_N 的topic信息
TOP_N=15

# 用于存储集群默认日志保留时间的全局变量
CLUSTER_DEFAULT_RETENTION_MS=""
CLUSTER_DEFAULT_RETENTION_SOURCE=""

# ===================================================================================
# Core Functions
# ===================================================================================

# 检查核心配置是否已被初始化
check_config() {
    if [ -z "$KAFKA_HOME" ] || [ -z "$ZK_CONNECT" ]; then
        echo "错误: 脚本配置缺失。请先运行 './$(basename "$0") init' 来自动发现并持久化配置。" >&2
        exit 1
    fi
}

# 内部函数: 获取集群的默认日志保留策略
# 这个函数会设置两个全局变量:
# - CLUSTER_DEFAULT_RETENTION_MS: 默认保留时间的毫秒数
# - CLUSTER_DEFAULT_RETENTION_SOURCE: 配置来源 (例如 "server.properties")
_get_cluster_default_retention() {
    # 使用静态变量来缓存结果，避免在同一次脚本执行中重复查询
    if [ -n "$CLUSTER_DEFAULT_RETENTION_MS" ]; then
        return
    fi
    
    echo "正在查询集群默认日志保留时间 (按优先级 ms > minutes > hours)..." >&2
    
    local ANY_BROKER_ID=$(${KAFKA_HOME}/bin/kafka-run-class.sh kafka.tools.ZooKeeperMainServer --zookeeper-connect ${ZK_CONNECT} ls /brokers/ids 2>/dev/null | tail -n 1 | grep -oE '[0-9]+' | head -n 1)
    if [ -z "$ANY_BROKER_ID" ]; then
        # 备用方案，兼容旧版 zookeeper-shell
        ANY_BROKER_ID=$(echo "ls /brokers/ids" | ${KAFKA_HOME}/bin/zookeeper-shell.sh ${ZK_CONNECT} 2>/dev/null | sed -n 's/.*\[\([^]]*\)\].*/\1/p' | tr ',' ' ' | cut -d' ' -f1)
    fi

    local BROKER_CONFIGS=$(${KAFKA_HOME}/bin/kafka-configs.sh --zookeeper ${ZK_CONNECT} --describe --entity-type brokers --entity-name ${ANY_BROKER_ID} 2>/dev/null)
    
    local RETENTION_MS=""
    local SOURCE=""
    
    # 1. 检查动态配置
    local VALUE=$(echo "${BROKER_CONFIGS}" | grep "log.retention.ms" | sed 's/.*log.retention.ms=\([0-9]*\).*/\1/')
    if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
        RETENTION_MS=${VALUE}
        SOURCE="(来自 Broker ${ANY_BROKER_ID} 动态配置)"
    fi
    
    if [ -z "$RETENTION_MS" ]; then
        VALUE=$(echo "${BROKER_CONFIGS}" | grep "log.retention.minutes" | sed 's/.*log.retention.minutes=\([0-9]*\).*/\1/')
        if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
            RETENTION_MS=$((VALUE * 60 * 1000))
            SOURCE="(来自 Broker ${ANY_BROKER_ID} 动态配置)"
        fi
    fi
    
    if [ -z "$RETENTION_MS" ]; then
        VALUE=$(echo "${BROKER_CONFIGS}" | grep "log.retention.hours" | sed 's/.*log.retention.hours=\([0-9]*\).*/\1/')
        if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
            RETENTION_MS=$((VALUE * 60 * 60 * 1000))
            SOURCE="(来自 Broker ${ANY_BROKER_ID} 动态配置)"
        fi
    fi
    
    # 2. 检查 server.properties 配置文件
    local CONFIG_FILE="${KAFKA_HOME}/config/server.properties"
    if [[ -z "$RETENTION_MS" && -f "${CONFIG_FILE}" ]]; then
        VALUE=$(grep -E "^log.retention.ms=" ${CONFIG_FILE} | cut -d'=' -f2 | tr -d '[:space:]')
        if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
            RETENTION_MS=${VALUE}
            SOURCE="(来自 server.properties)"
        fi
    
        if [ -z "$RETENTION_MS" ]; then
            VALUE=$(grep -E "^log.retention.minutes=" ${CONFIG_FILE} | cut -d'=' -f2 | tr -d '[:space:]')
            if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
                RETENTION_MS=$((VALUE * 60 * 1000))
                SOURCE="(来自 server.properties)"
            fi
        fi
    
        if [ -z "$RETENTION_MS" ]; then
            VALUE=$(grep -E "^log.retention.hours=" ${CONFIG_FILE} | cut -d'=' -f2 | tr -d '[:space:]')
            if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
                RETENTION_MS=$((VALUE * 60 * 60 * 1000))
                SOURCE="(来自 server.properties)"
            fi
        fi
    fi
    
    # 3. 使用 Kafka 内置的默认值
    if [ -z "$RETENTION_MS" ]; then
        RETENTION_MS=604800000
        SOURCE="(来自 Kafka 内置默认)"
    fi
    
    # 设置全局变量
    CLUSTER_DEFAULT_RETENTION_MS=${RETENTION_MS}
    CLUSTER_DEFAULT_RETENTION_SOURCE=${SOURCE}
}


# 自动发现 Kafka Home 和 Zookeeper Connect
discover_kafka_env() {
    echo "步骤 1: 正在自动发现 Kafka 环境..."

    # 1. 查找 Kafka 进程
    KAFKA_PROCESS_INFO=$(ps -ef | grep kafka.Kafka | grep -v grep)
    if [ -z "$KAFKA_PROCESS_INFO" ]; then
        echo "错误: 未找到正在运行的 Kafka Broker 进程。" >&2
        echo "请确保 Kafka 正在运行，并且当前用户有权限查看其进程。" >&2
        exit 1
    fi

    # 2. 从进程信息中提取 KAFKA_HOME
    local KAFKA_HOME_TEMP=""
    # 优先通过 kafka-server-start.sh 的路径推断
    local KAFKA_SCRIPT_PATH=$(echo "$KAFKA_PROCESS_INFO" | grep -oE '/[^ ]+/bin/kafka-server-start.sh' | head -n 1)
    if [ -n "$KAFKA_SCRIPT_PATH" ]; then
        KAFKA_HOME_TEMP=$(dirname $(dirname "$KAFKA_SCRIPT_PATH"))
    else
        # 备用方案: 从 classpath 中匹配核心 Kafka jar 包的路径来反推
        local KAFKA_LIBS_PATH=$(echo "$KAFKA_PROCESS_INFO" | grep -oE '/[^: ]+/libs/kafka_[^/]+\.jar' | head -n 1)
        if [ -n "$KAFKA_LIBS_PATH" ]; then
             KAFKA_HOME_TEMP=$(dirname $(dirname "$KAFKA_LIBS_PATH"))
        fi
    fi

    if [ -n "$KAFKA_HOME_TEMP" ]; then
        # 使用 cd 和 pwd 来解析路径中的 '..', 得到一个干净的、规范化的绝对路径
        KAFKA_HOME_DISCOVERED=$(cd "$KAFKA_HOME_TEMP" && pwd)
    else
        echo "错误: 无法从 Kafka 进程信息中自动确定 KAFKA_HOME。" >&2
        echo "这可能是因为进程信息格式特殊。请尝试手动在脚本中配置 KAFKA_HOME。" >&2
        echo "原始进程信息: $KAFKA_PROCESS_INFO" >&2
        exit 1
    fi

    # 3. 从进程信息中提取 ZK_CONNECT (仅取第一个节点)
    local OVERRIDE_ZK=$(echo "$KAFKA_PROCESS_INFO" | grep -oE 'zookeeper.connect=[^ ]+' | cut -d'=' -f2- | cut -d',' -f1)
    if [ -n "$OVERRIDE_ZK" ]; then
        ZK_CONNECT_DISCOVERED=$OVERRIDE_ZK
    else
        local SERVER_PROPS_PATH=$(echo "$KAFKA_PROCESS_INFO" | grep -oE '/[^ ]+/config/server.properties' | head -n 1)
        [ -z "$SERVER_PROPS_PATH" ] && SERVER_PROPS_PATH="${KAFKA_HOME_DISCOVERED}/config/server.properties"

        if [ -f "$SERVER_PROPS_PATH" ]; then
            ZK_CONNECT_DISCOVERED=$(grep -E "^zookeeper.connect=" "$SERVER_PROPS_PATH" | cut -d'=' -f2 | tr -d '[:space:]' | cut -d',' -f1)
            if [ -z "$ZK_CONNECT_DISCOVERED" ]; then
                echo "错误: 在配置文件 ${SERVER_PROPS_PATH} 中未找到 'zookeeper.connect' 配置。" >&2
                exit 1
            fi
        else
            echo "错误: 找不到 Kafka 配置文件: ${SERVER_PROPS_PATH}。" >&2
            exit 1
        fi
    fi
    
    # 将发现的值赋给全局变量，供 `persist_config` 使用
    KAFKA_HOME=${KAFKA_HOME_DISCOVERED}
    ZK_CONNECT=${ZK_CONNECT_DISCOVERED}
    
    echo "  > 环境发现成功!"
}

# 将发现的配置持久化到脚本自身
persist_config() {
    local script_path="$0"
    echo "步骤 2: 正在将配置持久化到脚本 (${script_path})..."

    # 使用 sed -i.bak 创建备份，以防万一
    sed -i.bak \
        -e "s#^KAFKA_HOME=.*#KAFKA_HOME=\"${KAFKA_HOME}\"#" \
        -e "s#^ZK_CONNECT=.*#ZK_CONNECT=\"${ZK_CONNECT}\"#" \
        "${script_path}"

    if [ $? -eq 0 ]; then
        rm "${script_path}.bak" # 成功后删除备份
        echo "  > 配置已成功更新并持久化。"
        echo "    - KAFKA_HOME: ${KAFKA_HOME}"
        echo "    - ZK_CONNECT: ${ZK_CONNECT}"
        echo ""
        echo "现在您可以直接运行其他命令了。"
    else
        echo "错误: 自动更新脚本配置失败。备份文件保留为 ${script_path}.bak" >&2
        exit 1
    fi
}

# ===================================================================================
# Command Functions
# ===================================================================================

# 内部函数: 将时间字符串 (如 3d, 12h) 转换为毫秒
_parse_time_to_ms() {
    local time_str="$1"
    local unit=$(echo "$time_str" | tr -d '0-9')
    local value=$(echo "$time_str" | tr -d 'a-zA-Z')

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "错误: 无效的时间数值 '$value'" >&2
        return 1
    fi

    case "$unit" in
        d)
            echo $((value * 24 * 60 * 60 * 1000))
            ;;
        h)
            echo $((value * 60 * 60 * 1000))
            ;;
        min)
            echo $((value * 60 * 1000))
            ;;
        ms|"") # 允许纯数字作为毫秒
            echo "$value"
            ;;
        *)
            echo "错误: 不支持的时间单位 '$unit'。请使用 d, h, min 或 ms。" >&2
            return 1
            ;;
    esac
}

# 命令: retention
# 功能: 查看或修改 Topic 的数据保留时间
cmd_retention() {
    check_config

    # --- retention 命令参数解析 ---
    if [ -z "$1" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        show_retention_help
        exit 0
    fi

    local topic_name="$1"
    shift

    # --- 修改操作 ---
    if [ "$1" == "--set" ]; then
        if [ -z "$2" ]; then
            echo "错误: --set 选项需要一个时间参数。" >&2
            show_retention_help
            exit 1
        fi
        local new_retention_str="$2"
        local new_retention_ms=$(_parse_time_to_ms "$new_retention_str")
        
        if [ $? -ne 0 ]; then
            exit 1 # _parse_time_to_ms 已经打印了错误信息
        fi

        echo "正在修改 Topic '${topic_name}' 的保留时间为 ${new_retention_str} (${new_retention_ms}ms)..."
        ${KAFKA_HOME}/bin/kafka-configs.sh --zookeeper ${ZK_CONNECT} --entity-type topics --entity-name "${topic_name}" \
            --alter --add-config retention.ms=${new_retention_ms} &>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "  > 修改成功。"
            echo "请注意: 配置变更可能需要一些时间在整个集群生效。"
        else
            echo "错误: 修改 Topic 配置失败。请检查 Topic 名称是否正确以及是否有权限执行此操作。" >&2
            exit 1
        fi
        exit 0
    fi

    # --- 查看操作 ---
    echo "正在查询 Topic '${topic_name}' 的数据保留时间..."
    local topic_config=$(${KAFKA_HOME}/bin/kafka-configs.sh --zookeeper ${ZK_CONNECT} --describe --entity-type topics --entity-name "${topic_name}" 2>/dev/null)
    
    local retention_ms=$(echo "${topic_config}" | grep "retention.ms" | sed 's/.*retention.ms=\([0-9]*\).*/\1/')
    local retention_str=""

    if [[ -n "$retention_ms" && "$retention_ms" =~ ^[0-9]+$ && "$retention_ms" -gt 0 ]]; then
        local retention_hours=$((retention_ms / 1000 / 60 / 60))
        retention_str="retention.ms=${retention_ms}（${retention_hours}小时）"
    else
        _get_cluster_default_retention # 确保默认值已被加载
        local default_hours=$((CLUSTER_DEFAULT_RETENTION_MS / 1000 / 60 / 60))
        retention_str="retention.ms=${CLUSTER_DEFAULT_RETENTION_MS}（${default_hours}小时）[默认]"
    fi
    
    # 模仿 stats 的输出格式以实现对齐
    (
      echo "Topic名称 保留策略"
      echo "${topic_name} ${retention_str}"
    ) | column -t
}

# 命令: init
# 功能: 初始化脚本配置
cmd_init() {
    discover_kafka_env
    persist_config
}

# 命令: stats (原脚本核心功能)
# 功能: 显示 Topic 磁盘占用统计
cmd_stats() {
    # --- stats 命令专属的参数解析 ---
    local TOP_N_OVERRIDE=""
    # 在循环外复制一份参数，以便安全地移位(shift)
    local args=("$@") 
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -h|--help)
                show_stats_help
                exit 0
                ;;
            --top)
                # 检查 --top 后面是否跟了有效的数字
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    TOP_N_OVERRIDE="$2"
                    shift 2 # 移掉 --top 和它的值
                else
                    echo "错误: --top 选项需要一个有效的数字参数。" >&2
                    echo "示例: ${SCRIPT_NAME} stats --top 10" >&2
                    exit 1
                fi
                ;;
            *)
                echo "错误: 'stats' 命令不支持选项 '$1'" >&2
                show_stats_help
                exit 1
                ;;
        esac
    done

    # 如果用户提供了 --top，则使用用户的值；否则，使用脚本顶部的全局默认值 TOP_N
    local current_top_n=${TOP_N_OVERRIDE:-$TOP_N}

    check_config # 每个业务命令前都检查配置

    echo "步骤 1: 正在从 Zookeeper ($ZK_CONNECT) 发现 Broker 列表..."
    BROKER_IDS_RAW=$(echo "ls /brokers/ids" | ${KAFKA_HOME}/bin/zookeeper-shell.sh ${ZK_CONNECT} 2>/dev/null | sed -n 's/.*\[\(.*\)\].*/\1/p')
    BROKER_IDS=$(echo ${BROKER_IDS_RAW} | tr ',' ' ')
    if [ -z "$BROKER_IDS" ]; then
        echo "错误: 未能从 Zookeeper 中发现任何 Broker ID。"
        exit 1
    fi

    echo "发现 Broker 列表:"
    BROKER_ENDPOINTS=()
    for id in ${BROKER_IDS}; do
      endpoint=$(${KAFKA_HOME}/bin/zookeeper-shell.sh ${ZK_CONNECT} 2>/dev/null <<< "get /brokers/ids/$id" | grep -oP 'PLAINTEXT://\K[^"]+')
      if [ -n "$endpoint" ]; then
        printf "  Broker %-3s => %s\n" "$id" "$endpoint"
        BROKER_ENDPOINTS+=("$endpoint")
      fi
    done

    if [ ${#BROKER_ENDPOINTS[@]} -eq 0 ]; then
        echo "错误: 未能从 Zookeeper 中发现任何 Broker。"
        exit 1
    fi

    BROKER_LIST=$(IFS=,; echo "${BROKER_ENDPOINTS[*]}")
    echo ""

    echo "步骤 2: 正在查询集群默认日志保留时间 (按优先级 ms > minutes > hours)..."
    _get_cluster_default_retention # 调用新的公共函数
    
    DEFAULT_RETENTION_STR=""
    if [[ -n "$CLUSTER_DEFAULT_RETENTION_MS" && "$CLUSTER_DEFAULT_RETENTION_MS" =~ ^[0-9]+$ ]]; then
        DEFAULT_RETENTION_HOURS=$((CLUSTER_DEFAULT_RETENTION_MS / 1000 / 60 / 60))
        DEFAULT_RETENTION_STR="retention.ms=${CLUSTER_DEFAULT_RETENTION_MS}（${DEFAULT_RETENTION_HOURS}小时）[默认]"
        echo "集群默认保留时间: ${DEFAULT_RETENTION_HOURS}小时 (${CLUSTER_DEFAULT_RETENTION_MS}ms)${CLUSTER_DEFAULT_RETENTION_SOURCE}"
    else
        DEFAULT_RETENTION_STR="retention.ms=无法获取默认值"
        echo "警告: 未能获取到集群默认日志保留时间。"
    fi
    echo ""
    
    echo "步骤 3: 正在计算 Top ${current_top_n} Topic 的磁盘占用..."
    
    TOP_TOPICS_DATA=$(${KAFKA_HOME}/bin/kafka-log-dirs.sh --bootstrap-server ${BROKER_LIST} --describe 2>/dev/null | \
    sed -e 's/},{/}\n{/g' | \
    grep '"partition":' | \
    sed -e 's/.*"partition":"\([^"]*\)","size":\([0-9]*\).*/\1 \2/' | \
    awk '{
           topic_partition=$1;
           size_in_bytes=$2;
           sub(/-[0-9]+$/, "", topic_partition);
           sum[topic_partition] += size_in_bytes;
         }
         END {
           for(t in sum) printf "%.1fG\t%s\n", sum[t]/1024/1024/1024, t
         }' | \
    sort -hr | \
    head -n ${current_top_n})
    
    (
    echo "大小 Topic名称 保留策略"
    
    echo "$TOP_TOPICS_DATA" | while read -r size topic; do
        RETENTION_MS=$(${KAFKA_HOME}/bin/kafka-configs.sh --zookeeper ${ZK_CONNECT} --describe --entity-type topics --entity-name ${topic} 2>/dev/null | grep "retention.ms" | sed 's/.*retention.ms=\([0-9]*\).*/\1/')
    
        RETENTION_STR=""
        if [[ -n "$RETENTION_MS" && "$RETENTION_MS" =~ ^[0-9]+$ && "$RETENTION_MS" -gt 0 ]]; then
            RETENTION_HOURS=$((RETENTION_MS / 1000 / 60 / 60))
            RETENTION_STR="retention.ms=${RETENTION_MS}（${RETENTION_HOURS}小时）"
        else
            RETENTION_STR="${DEFAULT_RETENTION_STR}"
        fi
    
        echo "${size} ${topic} ${RETENTION_STR}"
    done
    ) | column -t
}

show_stats_help() {
    echo "用法: ${SCRIPT_NAME} stats [选项]"
    echo ""
    echo "显示集群的常用统计数据：broker节点、topic磁盘占用 Top N、这些topic的保留时间"
    echo ""
    echo "选项:"
    echo "  --top <N>    指定显示的 Topic 数量。默认为 ${TOP_N}。"
    echo "  -h, --help   显示此帮助信息。"
    echo ""
    echo "示例:"
    echo "  ${SCRIPT_NAME} stats          # 显示 Top ${TOP_N} Topic"
    echo "  ${SCRIPT_NAME} stats --top 5  # 显示 Top 5 Topic"
}

show_retention_help() {
    echo "用法: ${SCRIPT_NAME} retention <topic名称> [选项]"
    echo ""
    echo "查看或修改指定 Topic 的数据保留时间。"
    echo ""
    echo "选项:"
    echo "  --set <时间>   设置新的数据保留时间。支持的单位: d(天), h(小时), min(分钟), ms(或纯数字)。"
    echo "  -h, --help     显示此帮助信息。"
    echo ""
    echo "示例:"
    echo "  ${SCRIPT_NAME} retention my-topic              # 查看 'my-topic' 的保留时间"
    echo "  ${SCRIPT_NAME} retention my-topic --set 7d       # 将 'my-topic' 的保留时间设置为 7 天"
    echo "  ${SCRIPT_NAME} retention my-topic --set 12h      # 设置为 12 小时"
    echo "  ${SCRIPT_NAME} retention my-topic --set 86400000 # 设置为 86400000 毫秒"
}

show_help() {
    echo "${SCRIPT_NAME} - 一个用于简化 Kafka 日常运维的命令行工具。"
    echo ""
    echo "用法: "
    echo "  ${SCRIPT_NAME} <命令> [选项...]"
    echo ""
    echo "可用命令:"
    echo "  init         自动发现并持久化 Kafka 环境配置到脚本中 (首次使用必须运行此命令)"
    echo "  retention    查看或修改指定 Topic 的数据保留时间"
    echo "  stats        显示集群的常用统计数据：broker节点、topic磁盘占用Top N、这些topic的保留时间"
    echo "  help         显示此帮助信息"
    echo ""
}

# ===================================================================================
# Main Execution Logic
# ===================================================================================

COMMAND=$1
shift || true # 如果没有参数, shift 会失败, `|| true` 可以防止脚本退出

case "$COMMAND" in
    init)
        cmd_init
        ;;

    stats)
        cmd_stats "$@"
        ;;

    retention)
        cmd_retention "$@"
        ;;

    "" | "help" | "-h" | "--help")
        show_help
        ;;

    *)
        echo "错误: 未知命令 '$COMMAND'" >&2
        echo ""
        show_help
        exit 1
        ;;
esac