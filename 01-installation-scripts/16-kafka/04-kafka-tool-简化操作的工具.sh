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

    # 3. 从进程信息中提取 ZK_CONNECT
    local OVERRIDE_ZK=$(echo "$KAFKA_PROCESS_INFO" | grep -oE 'zookeeper.connect=[^ ]+' | cut -d'=' -f2-)
    if [ -n "$OVERRIDE_ZK" ]; then
        ZK_CONNECT_DISCOVERED=$OVERRIDE_ZK
    else
        local SERVER_PROPS_PATH=$(echo "$KAFKA_PROCESS_INFO" | grep -oE '/[^ ]+/config/server.properties' | head -n 1)
        [ -z "$SERVER_PROPS_PATH" ] && SERVER_PROPS_PATH="${KAFKA_HOME_DISCOVERED}/config/server.properties"

        if [ -f "$SERVER_PROPS_PATH" ]; then
            ZK_CONNECT_DISCOVERED=$(grep -E "^zookeeper.connect=" "$SERVER_PROPS_PATH" | cut -d'=' -f2 | tr -d '[:space:]')
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
    
}

# 将发现的配置持久化到脚本自身
persist_config() {
    local script_path="$0"

    # 使用 sed -i.bak 创建备份，以防万一
    sed -i.bak \
        -e "s#^KAFKA_HOME=.*#KAFKA_HOME=\"${KAFKA_HOME}\"#" \
        -e "s#^ZK_CONNECT=.*#ZK_CONNECT=\"${ZK_CONNECT}\"#" \
        "${script_path}"

    if [ $? -eq 0 ]; then
        rm "${script_path}.bak" # 成功后删除备份
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
    if [ "$1" == "--all" ]; then
        shift # consume --all

        echo "正在查询所有 Topic 的数据保留时间..."
        _get_cluster_default_retention # 确保默认值已被加载

        local default_retention_str=""
        if [[ -n "$CLUSTER_DEFAULT_RETENTION_MS" && "$CLUSTER_DEFAULT_RETENTION_MS" =~ ^[0-9]+$ ]]; then
            local default_hours=$((CLUSTER_DEFAULT_RETENTION_MS / 1000 / 60 / 60))
            default_retention_str="retention.ms=${CLUSTER_DEFAULT_RETENTION_MS}（${default_hours}小时）[默认]"
            echo "集群默认保留时间: ${default_hours}小时 (${CLUSTER_DEFAULT_RETENTION_MS}ms)${CLUSTER_DEFAULT_RETENTION_SOURCE}"
        else
            default_retention_str="retention.ms=无法获取默认值"
            echo "警告: 未能获取到集群默认日志保留时间。"
        fi
        
        local topics_list
        topics_list=$(${KAFKA_HOME}/bin/kafka-topics.sh --zookeeper ${ZK_CONNECT} --list | sort)
        
        # 过滤掉空行再计数
        local total_topics
        total_topics=$(echo "$topics_list" | sed '/^$/d' | wc -l | tr -d ' ')

        if [ "$total_topics" -eq 0 ]; then
            echo "未发现任何 Topic。"
            exit 0
        fi
        
        echo "发现 ${total_topics} 个 Topic，开始查询保留策略..."

        (
            echo "Topic名称 保留策略"
            local processed_count=0
            # 列出并排序所有 topic
            echo "$topics_list" | while read -r topic; do
                if [ -z "$topic" ]; then continue; fi

                processed_count=$((processed_count + 1))
                # 查询所有 topic 时默认显示进度
                local progress_str="查询进度: ${processed_count}/${total_topics} - ${topic}"
                printf "\r%-80s" "${progress_str}" >&2

                local topic_config=$(${KAFKA_HOME}/bin/kafka-configs.sh --zookeeper ${ZK_CONNECT} --describe --entity-type topics --entity-name "${topic}" 2>/dev/null)
                local retention_ms=$(echo "${topic_config}" | grep "retention.ms" | sed 's/.*retention.ms=\([0-9]*\).*/\1/')
                local retention_str=""

                if [[ -n "$retention_ms" && "$retention_ms" =~ ^[0-9]+$ && "$retention_ms" -gt 0 ]]; then
                    local retention_hours=$((retention_ms / 1000 / 60 / 60))
                    retention_str="retention.ms=${retention_ms}（${retention_hours}小时）"
                    # 如果当前topic的保留时间和集群默认值相同，则添加[默认]标记
                    if [[ -n "$CLUSTER_DEFAULT_RETENTION_MS" && "$retention_ms" == "$CLUSTER_DEFAULT_RETENTION_MS" ]]; then
                        retention_str="${retention_str}[默认]"
                    fi
                else
                    retention_str="${default_retention_str}"
                fi
                echo "${topic} ${retention_str}"
            done
            
            # 清空进度条行，避免与输出混在一起
            printf "\r%-80s\r" "" >&2
        ) | column -t
        
        # 结束时，用完成信息覆盖进度条并换行
        printf "查询完成。共处理 %d 个 Topic。\n" "$total_topics" >&2

        exit 0
    fi

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

    # --- 删除操作 ---
    if [ "$1" == "--delete" ]; then
        echo "正在删除 '${topic_name}' 的保留时间配置..."
        local output
        output=$(${KAFKA_HOME}/bin/kafka-configs.sh --zookeeper ${ZK_CONNECT} --entity-type topics --entity-name "${topic_name}" \
            --alter --delete-config retention.ms 2>&1)
        local exit_code=$?

        if [ ${exit_code} -eq 0 ]; then
            echo "  > 删除成功, topic将使用集群默认值。"
        # The command fails if the config is not set. We treat this as a success.
        elif [[ "${output}" == *"Invalid config(s): retention.ms"* ]]; then
            echo "  > 配置本未设置, 无需删除。"
        else
            echo "错误: 删除 Topic 配置失败。" >&2
            echo "--- Kafka 命令输出 ---" >&2
            echo "${output}" >&2
            echo "-----------------------" >&2
            exit 1
        fi
        exit 0
    fi

    # --- 查看操作 ---
    echo "正在查询 Topic '${topic_name}' 的数据保留时间..."
    local topic_config=$(${KAFKA_HOME}/bin/kafka-configs.sh --zookeeper ${ZK_CONNECT} --describe --entity-type topics --entity-name "${topic_name}" 2>/dev/null)
    
    local retention_ms=$(echo "${topic_config}" | grep "retention.ms" | sed 's/.*retention.ms=\([0-9]*\).*/\1/')
    local retention_str=""

    _get_cluster_default_retention # 确保默认值已被加载

    if [[ -n "$retention_ms" && "$retention_ms" =~ ^[0-9]+$ && "$retention_ms" -gt 0 ]]; then
        local retention_hours=$((retention_ms / 1000 / 60 / 60))
        retention_str="retention.ms=${retention_ms}（${retention_hours}小时）"
        # 如果当前topic的保留时间和集群默认值相同，则添加[默认]标记
        if [[ "$retention_ms" == "$CLUSTER_DEFAULT_RETENTION_MS" ]]; then
            retention_str="${retention_str}[默认]"
        fi
    else
        # Fallback in case retention.ms is not found, which is unlikely but safe to keep
        local default_hours=$((CLUSTER_DEFAULT_RETENTION_MS / 1000 / 60 / 60))
        retention_str="retention.ms=${CLUSTER_DEFAULT_RETENTION_MS}（${default_hours}小时）[默认]"
    fi
    
    # 模仿 stats 的输出格式以实现对齐
    (
      echo "Topic名称 保留策略"
      echo "${topic_name} ${retention_str}"
    ) | column -t
}

# 命令: topic
# 功能: Topic 相关操作
cmd_topic() {
    check_config

    local sub_command="$1"
    shift || true

    case "$sub_command" in
        list)
            echo "正在查询集群所有 Topic..."
            ${KAFKA_HOME}/bin/kafka-topics.sh --zookeeper ${ZK_CONNECT} --list
            ;;
        "" | "-h" | "--help")
            show_topic_help
            ;;
        *)
            echo "错误: 'topic' 命令不支持子命令 '$sub_command'" >&2
            show_topic_help
            exit 1
            ;;
    esac
}

# 命令: isr
# 功能: 查询 Topic 分区的 ISR (In-Sync Replicas) 状态
cmd_isr() {
    check_config

    local show_all=false
    local under_replicated_only=false
    local topic_name=""

    # --- isr 命令参数解析 ---
    local args=("$@") # 复制参数以安全地进行操作
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                show_all=true
                shift
                ;;
            --under-replicated-only)
                under_replicated_only=true
                show_all=true  # --under-replicated-only 隐含查询所有 topic
                shift
                ;;
            -h|--help)
                show_isr_help
                exit 0
                ;;
            *)
                if [[ -z "$topic_name" && ! "$1" =~ ^- ]]; then
                    topic_name="$1"
                    shift
                else
                    echo "错误: 未知或无效的选项 '$1'" >&2
                    show_isr_help
                    exit 1
                fi
                ;;
        esac
    done

    if ! $show_all && [ -z "$topic_name" ]; then
        show_isr_help
        exit 0
    fi

    if $show_all && [ -n "$topic_name" ]; then
        echo "错误: 不能同时指定 Topic 名称和 --all 选项。" >&2
        show_isr_help
        exit 1
    fi

    # --- AWK 脚本用于解析和格式化 describe 命令的输出 ---
    local awk_script='
        # 只处理包含 Partition 关键字的行
        /Partition:/ {
            topic = $2;
            partition = $4;
            leader = $6;
            replicas = $8;
            isr = $10;

            # 计算 Replicas 和 Isr 列表中的元素数量
            n_replicas = split(replicas, r_arr, ",");
            n_isr = split(isr, i_arr, ",");
            
            status = (n_isr < n_replicas) ? "UNDER-REPLICATED" : "OK";

            # 根据 --under-replicated-only 标志进行过滤
            if (under_replicated == "true" && status == "OK") {
                next;
            }

            printf "%s %s %s %s %s %s\n", topic, partition, leader, replicas, isr, status;
        }
    '

    # --- 逻辑执行 ---
    if ! $show_all; then
        echo "正在查询 Topic '${topic_name}' 的 ISR 状态..."
        local isr_output
        isr_output=$(${KAFKA_HOME}/bin/kafka-topics.sh --zookeeper ${ZK_CONNECT} --describe --topic "${topic_name}" 2>/dev/null | \
            awk -v under_replicated="${under_replicated_only}" "${awk_script}")
        
        if [ -z "$isr_output" ]; then
            if [ "$under_replicated_only" = true ]; then
                echo "所有分区的 ISR 状态均正常。"
            fi
        else
            (
                echo "Topic Partition Leader Replicas Isr Status"
                echo "$isr_output"
            ) | column -t
        fi
    else
        local topics_list
        topics_list=$(${KAFKA_HOME}/bin/kafka-topics.sh --zookeeper ${ZK_CONNECT} --list | sort)
        
        local total_topics
        total_topics=$(echo "$topics_list" | sed '/^$/d' | wc -l | tr -d ' ')

        if [ "$total_topics" -eq 0 ]; then
            echo "未发现任何 Topic。"
            exit 0
        fi

        echo "发现 ${total_topics} 个 Topic，开始查询 ISR 状态..."
        
        # 临时文件用于存储输出
        local temp_output=$(mktemp)
        
        (
            local processed_count=0
            
            echo "$topics_list" | while read -r topic; do
                if [ -z "$topic" ]; then continue; fi

                processed_count=$((processed_count + 1))
                # 查询所有 topic 时默认显示进度
                local progress_str="查询进度: ${processed_count}/${total_topics} - ${topic}"
                printf "\r%-80s" "${progress_str}" >&2

                ${KAFKA_HOME}/bin/kafka-topics.sh --zookeeper ${ZK_CONNECT} --describe --topic "${topic}" 2>/dev/null | \
                    awk -v under_replicated="${under_replicated_only}" "${awk_script}"
            done
        ) > "$temp_output"
        
        # 清空进度条行
        printf "\r%-80s\r" "" >&2
        
        # 检查是否有数据
        if [ -s "$temp_output" ]; then
            (
                echo "Topic Partition Leader Replicas Isr Status"
                cat "$temp_output"
            ) | column -t
        else
            if [ "$under_replicated_only" = true ]; then
                echo "所有分区的 ISR 状态均正常。"
            fi
        fi
        
        rm -f "$temp_output"
        
        printf "查询完成。共处理 %d 个 Topic。\n" "$total_topics" >&2
    fi
}

# 命令: init
# 功能: 初始化脚本配置
cmd_init() {
    if [[ "$1" == "show" ]]; then
        check_config
        echo "KAFKA_HOME: ${KAFKA_HOME}"
        echo "ZK_CONNECT: ${ZK_CONNECT}"
        exit 0
    fi
    discover_kafka_env
    persist_config
    echo "KAFKA_HOME: ${KAFKA_HOME}"
    echo "ZK_CONNECT: ${ZK_CONNECT}"
}

# 内部函数: 格式化字节大小为人类可读格式
_format_size() {
    local bytes="$1"
    
    # 处理空值或无效值
    if [ -z "$bytes" ]; then
        echo "0.00M"
        return
    fi
    
    # 确保是数字
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        echo "0.00M"
        return
    fi
    
    # 处理 0
    if [ "$bytes" -eq 0 ]; then
        echo "0.00M"
        return
    fi
    
    # 使用 AWK 来判断并格式化，避免 bash 整数溢出问题
    awk -v bytes="$bytes" 'BEGIN {
        tb = 1024 * 1024 * 1024 * 1024;
        gb = 1024 * 1024 * 1024;
        
        if (bytes >= tb) {
            printf "%.2fT", bytes / tb;
        } else if (bytes >= gb) {
            printf "%.2fG", bytes / gb;
        } else {
            printf "%.2fM", bytes / (1024 * 1024);
        }
    }'
}

# 命令: size
# 功能: 查询 Topic 的磁盘占用大小
cmd_size() {
    check_config

    local show_all=false
    local topic_name=""
    local top_n=""

    # --- size 命令参数解析 ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                show_all=true
                shift
                ;;
            --top)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    top_n="$2"
                    show_all=true  # --top 隐含 --all
                    shift 2
                else
                    echo "错误: --top 选项需要一个有效的数字参数。" >&2
                    echo "示例: ${SCRIPT_NAME} size --top 10" >&2
                    exit 1
                fi
                ;;
            -h|--help)
                show_size_help
                exit 0
                ;;
            *)
                if [[ -z "$topic_name" && ! "$1" =~ ^- ]]; then
                    topic_name="$1"
                    shift
                else
                    echo "错误: 未知或无效的选项 '$1'" >&2
                    show_size_help
                    exit 1
                fi
                ;;
        esac
    done

    if ! $show_all && [ -z "$topic_name" ]; then
        show_size_help
        exit 0
    fi

    if $show_all && [ -n "$topic_name" ]; then
        echo "错误: 不能同时指定 Topic 名称和 --all/--top 选项。" >&2
        show_size_help
        exit 1
    fi

    # 获取 Broker 列表
    echo "正在从 Zookeeper 获取 Broker 信息..."
    BROKER_IDS_RAW=$(echo "ls /brokers/ids" | ${KAFKA_HOME}/bin/zookeeper-shell.sh ${ZK_CONNECT} 2>/dev/null | sed -n 's/.*\[\(.*\)\].*/\1/p')
    BROKER_IDS=$(echo ${BROKER_IDS_RAW} | tr ',' ' ')
    
    if [ -z "$BROKER_IDS" ]; then
        echo "错误: 未能从 Zookeeper 中发现任何 Broker ID。" >&2
        exit 1
    fi

    local broker_endpoints_str=""
    for id in ${BROKER_IDS}; do
        endpoint=$(${KAFKA_HOME}/bin/zookeeper-shell.sh ${ZK_CONNECT} 2>/dev/null <<< "get /brokers/ids/$id" | grep -oP 'PLAINTEXT://\K[^"]+')
        if [ -n "$endpoint" ]; then
            broker_endpoints_str="${broker_endpoints_str}${endpoint},"
        fi
    done
    BROKER_LIST=${broker_endpoints_str%,}

    echo "正在查询 Topic 磁盘占用信息..."
    LOG_DIRS_DATA=$(${KAFKA_HOME}/bin/kafka-log-dirs.sh --bootstrap-server ${BROKER_LIST} --describe 2>/dev/null)

    if [ -z "$LOG_DIRS_DATA" ]; then
        echo "错误: 未能获取日志目录数据。" >&2
        exit 1
    fi

    # 解析所有 topic 的大小
    declare -A TOPIC_SIZES
    while read -r topic size_bytes; do
        TOPIC_SIZES[$topic]=$size_bytes
    done < <(echo "$LOG_DIRS_DATA" | \
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
            for(t in sum) printf "%s %s\n", t, sum[t]
        }')

    # --- 逻辑执行 ---
    if ! $show_all; then
        # 查询单个 topic
        echo "正在查询 Topic '${topic_name}' 的磁盘占用..."
        
        local size_bytes=${TOPIC_SIZES[$topic_name]}
        if [ -z "$size_bytes" ]; then
            echo "错误: Topic '${topic_name}' 不存在或没有数据。" >&2
            exit 1
        fi
        
        local size_formatted=$(_format_size "$size_bytes")
        
        (
            echo "Topic名称 磁盘占用"
            echo "${topic_name} ${size_formatted}"
        ) | column -t
    else
        # 查询所有 topic
        local topics_list
        topics_list=$(${KAFKA_HOME}/bin/kafka-topics.sh --zookeeper ${ZK_CONNECT} --list | sort)
        
        local total_topics
        total_topics=$(echo "$topics_list" | sed '/^$/d' | wc -l | tr -d ' ')

        if [ "$total_topics" -eq 0 ]; then
            echo "未发现任何 Topic。"
            exit 0
        fi

        local display_count=${top_n:-$total_topics}
        if [ -n "$top_n" ]; then
            echo "发现 ${total_topics} 个 Topic，正在统计磁盘占用（显示 Top ${top_n}）..."
        else
            echo "发现 ${total_topics} 个 Topic，正在统计磁盘占用..."
        fi
        
        # 临时文件用于存储和排序
        local temp_output=$(mktemp)
        
        local processed_count=0
        for topic in $(echo "$topics_list"); do
            if [ -z "$topic" ]; then continue; fi
            
            processed_count=$((processed_count + 1))
            local progress_str="统计进度: ${processed_count}/${total_topics}"
            printf "\r%-80s" "${progress_str}" >&2
            
            local size_bytes=${TOPIC_SIZES[$topic]:-0}
            
            # 存储原始字节数用于排序，topic名称
            echo "${size_bytes} ${topic}" >> "$temp_output"
        done
        
        # 清空进度条行
        printf "\r%-80s\r" "" >&2
        
        (
            echo "磁盘占用 Topic名称"
            # 按字节数排序（数值排序，降序），然后格式化显示
            sort -rn "$temp_output" | head -n ${display_count} | while read -r bytes topic; do
                local formatted_size=$(_format_size "$bytes")
                echo "${formatted_size} ${topic}"
            done
        ) | column -t
        
        rm -f "$temp_output"
        
        if [ -n "$top_n" ]; then
            printf "查询完成。共处理 %d 个 Topic，显示前 %d 个。\n" "$total_topics" "$display_count" >&2
        else
            printf "查询完成。共处理 %d 个 Topic。\n" "$total_topics" >&2
        fi
    fi
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

    echo "步骤 1: 正在查询 Zookeeper ($ZK_CONNECT) 集群状态..."
    
    # 从 ZK_CONNECT 中提取服务器列表, 移除可能存在的 chroot 路径
    local zk_servers_with_chroot=$(echo "$ZK_CONNECT" | cut -d'/' -f1)
    # 将逗号替换为空格, 以便在 for 循环中迭代
    local zk_server_list=$(echo "$zk_servers_with_chroot" | tr ',' ' ')

    if [ -n "$zk_server_list" ]; then
        echo "Zookeeper 集群信息:"
        
        if ! command -v nc &> /dev/null; then
            echo "警告: 'nc' (netcat) 命令未找到。无法查询 Zookeeper 主从状态。" >&2
            echo "${ZK_CONNECT}"
        else
            # 阶段 1: 收集所有节点的状态和名称
            declare -a server_full_names
            declare -a server_hosts
            declare -a server_modes
            declare -a leader_indices
            local max_len=0
            
            local i=0
            for server in ${zk_server_list}; do
                local server_host=$(echo "$server" | cut -d':' -f1)
                local server_port=$(echo "$server" | cut -d':' -f2)
                [ -z "$server_port" ] && server_port="2181"
                
                local full_name="${server_host}:${server_port}"
                server_full_names[i]=$full_name
                server_hosts[i]=$server_host

                if [ ${#full_name} -gt $max_len ]; then
                    max_len=${#full_name}
                fi

                local mode_line=$(echo "srvr" | nc -w 2 ${server_host} ${server_port} 2>/dev/null | grep "Mode:")
                local mode="状态未知"
                if [ -n "$mode_line" ]; then
                    mode=$(echo "$mode_line" | sed 's/Mode: //')
                fi
                server_modes[i]=$mode

                if [[ "$mode" == "leader" ]]; then
                    leader_indices+=($i)
                fi
                i=$((i+1))
            done
            
            # 阶段 2: 根据 leader 数量决定输出格式
            local leader_count=${#leader_indices[@]}
            
            if [ ${leader_count} -le 1 ]; then
                # --- 简单模式: 0 或 1 个 leader, 保持原有风格 ---
                for ((j=0; j<${#server_full_names[@]}; j++)); do
                    printf "%-${max_len}s (%s)\n" "${server_full_names[j]}" "${server_modes[j]}"
                done
            else
                # --- 诊断模式: 多于 1 个 leader, 解析 IP 并添加备注 ---
                declare -a server_ips
                declare -A ip_to_first_host
                local output_data="Zookeeper节点 角色 备注\n"

                for ((j=0; j<${#server_hosts[@]}; j++)); do
                    local ip_addr=$(ping -c 1 ${server_hosts[j]} 2>/dev/null | head -n 1 | grep -oE '\([0-9\.]+\)' | tr -d '()')
                    [ -z "$ip_addr" ] && ip_addr="无法解析"
                    server_ips[j]=$ip_addr

                    if [[ "$ip_addr" != "无法解析" && -z "${ip_to_first_host[$ip_addr]}" ]]; then
                        ip_to_first_host[$ip_addr]="${server_hosts[j]}"
                    fi
                done

                for ((j=0; j<${#server_full_names[@]}; j++)); do
                    local note="-"
                    local ip_addr=${server_ips[j]}
                    if [[ "$ip_addr" != "无法解析" ]]; then
                        local first_host_for_ip=${ip_to_first_host[$ip_addr]}
                        if [[ "${server_hosts[j]}" != "$first_host_for_ip" ]]; then
                            note="IP同${first_host_for_ip}"
                        fi
                    fi
                    output_data+="${server_full_names[j]} ${server_modes[j]} ${note}\n"
                done

                printf "%b" "${output_data}" | column -t
                
                # 精准告警: 仅当 leader 的 IP 不同时才告警
                declare -A unique_leader_ips
                for leader_index in "${leader_indices[@]}"; do
                    local leader_ip=${server_ips[leader_index]}
                    if [[ "$leader_ip" != "无法解析" ]]; then
                        unique_leader_ips[$leader_ip]=1
                    fi
                done
                
                if [ ${#unique_leader_ips[@]} -ge 2 ]; then
                    echo ""
                    echo "警告: 在不同 IP 上检测到 ${#unique_leader_ips[@]} 个 Zookeeper Leader，可能存在脑裂风险！" >&2
                    echo "Leader IP 列表: ${!unique_leader_ips[@]}" >&2
                fi
            fi
        fi
        echo ""
    else
        echo "Zookeeper 集群信息: ${ZK_CONNECT} (无法解析服务器列表)"
        echo ""
    fi

    echo "步骤 2: 正在从 Zookeeper ($ZK_CONNECT) 发现 Broker 列表并统计日志信息..."
    BROKER_IDS_RAW=$(echo "ls /brokers/ids" | ${KAFKA_HOME}/bin/zookeeper-shell.sh ${ZK_CONNECT} 2>/dev/null | sed -n 's/.*\[\(.*\)\].*/\1/p')
    BROKER_IDS=$(echo ${BROKER_IDS_RAW} | tr ',' ' ')
    if [ -z "$BROKER_IDS" ]; then
        echo "错误: 未能从 Zookeeper 中发现任何 Broker ID。"
        exit 1
    fi

    local broker_endpoints_str=""
    for id in ${BROKER_IDS}; do
      endpoint=$(${KAFKA_HOME}/bin/zookeeper-shell.sh ${ZK_CONNECT} 2>/dev/null <<< "get /brokers/ids/$id" | grep -oP 'PLAINTEXT://\K[^"]+')
      if [ -n "$endpoint" ]; then
        broker_endpoints_str="${broker_endpoints_str}${endpoint},"
      fi
    done
    BROKER_LIST=${broker_endpoints_str%,} # 移除末尾的逗号

    LOG_DIRS_DATA=$(${KAFKA_HOME}/bin/kafka-log-dirs.sh --bootstrap-server ${BROKER_LIST} --describe 2>/dev/null)
    
    declare -A BROKER_SIZES
    declare -A BROKER_LOG_DIRS
    
    # 使用 AWK 解析 JSON 输出, 汇总每个 Broker 的总大小和 Log 目录
    # 使用进程替换 < <(...) 来避免在 subshell 中运行 while 循环, 确保数组变量在循环外可用
    while read -r id size_bytes dirs; do
        BROKER_SIZES[$id]=$size_bytes
        BROKER_LOG_DIRS[$id]=$dirs
    done < <(echo "$LOG_DIRS_DATA" | \
    awk 'BEGIN { RS="\"broker\":" } NR > 1 {
        broker_id = substr($0, 1, index($0, ",")-1);
        total_size = 0;
        
        record_for_size = $0;
        while (match(record_for_size, /"size":([0-9]+)/)) {
            total_size += substr(record_for_size, RSTART+7, RLENGTH-7);
            record_for_size = substr(record_for_size, RSTART+RLENGTH);
        }
        
        delete dirs;
        record_for_dirs = $0;
        while (match(record_for_dirs, /"logDir":"([^"]+)"/)) {
            dir = substr(record_for_dirs, RSTART+10, RLENGTH-11);
            dirs[dir] = 1;
            record_for_dirs = substr(record_for_dirs, RSTART+RLENGTH);
        }

        dir_list = "";
        for (d in dirs) {
            dir_list = (dir_list == "" ? d : dir_list "," d);
        }
        
        printf "%s %s %s\n", broker_id, total_size, dir_list
    }')

    # 获取本机所有 IP 地址, 用于识别本地 Broker
    local local_ips
    local_ips=$(hostname -I 2>/dev/null || ip -4 addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | tr '\n' ' ')

    (
        echo "BrokerID|Endpoint|总日志大小|本机磁盘使用率"
        for id in ${BROKER_IDS}; do
            endpoint=$(${KAFKA_HOME}/bin/zookeeper-shell.sh ${ZK_CONNECT} 2>/dev/null <<< "get /brokers/ids/$id" | grep -oP 'PLAINTEXT://\K[^"]+')
            if [ -n "$endpoint" ]; then
                size_bytes=${BROKER_SIZES[$id]:-0}
                log_dirs=${BROKER_LOG_DIRS[$id]}
                size_formatted=$(_format_size "$size_bytes")
                
                disk_usage=""
                local broker_ip=$(echo "$endpoint" | cut -d':' -f1)

                # 检查当前 Broker 是否为本机
                if [[ -n "$log_dirs" && "$local_ips" == *"$broker_ip"* ]]; then
                    # 如果有多个日志目录, 以第一个为准计算磁盘使用率
                    local first_log_dir=$(echo "$log_dirs" | cut -d',' -f1)
                    if [ -d "$first_log_dir" ]; then
                        local df_info
                        df_info=$(df -h --output=pcent,used,size,target "$first_log_dir" 2>/dev/null | tail -n 1)
                        if [ -n "$df_info" ]; then
                            local pcent used size target
                            read -r pcent used size target <<< "$df_info"
                            pcent=$(echo "$pcent" | tr -d '[:space:]')
                            disk_usage="${pcent} [${used}/${size}] ${target}"
                        fi
                    fi
                fi

                echo "$id|$endpoint|$size_formatted|$disk_usage"
            fi
        done
    ) | column -t -s '|' -o '  '
    echo ""

    echo "步骤 3: 正在查询集群默认日志保留时间 (按优先级 ms > minutes > hours)..."
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
    
    echo "步骤 4: 正在计算 Top ${current_top_n} Topic 的磁盘占用..."
    
    # 先计算每个 topic 的字节数，按字节数排序后取 Top N
    TOP_TOPICS_DATA=$(echo "$LOG_DIRS_DATA" | \
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
           for(t in sum) printf "%s\t%s\n", sum[t], t
         }' | \
    sort -rn | \
    head -n ${current_top_n})
    
    (
    echo "磁盘占用 Topic名称 保留策略"
    
    echo "$TOP_TOPICS_DATA" | while read -r size_bytes topic; do
        # 格式化大小显示
        size_formatted=$(_format_size "$size_bytes")
        
        RETENTION_MS=$(${KAFKA_HOME}/bin/kafka-configs.sh --zookeeper ${ZK_CONNECT} --describe --entity-type topics --entity-name ${topic} 2>/dev/null | grep "retention.ms" | sed 's/.*retention.ms=\([0-9]*\).*/\1/')
    
        RETENTION_STR=""
        if [[ -n "$RETENTION_MS" && "$RETENTION_MS" =~ ^[0-9]+$ && "$RETENTION_MS" -gt 0 ]]; then
            RETENTION_HOURS=$((RETENTION_MS / 1000 / 60 / 60))
            RETENTION_STR="retention.ms=${RETENTION_MS}（${RETENTION_HOURS}小时）"
            # 如果当前topic的保留时间和集群默认值相同，则添加[默认]标记
            # 注意: 此处的 CLUSTER_DEFAULT_RETENTION_MS 已经在循环外由 _get_cluster_default_retention 获取并设置了
            if [[ "$RETENTION_MS" == "$CLUSTER_DEFAULT_RETENTION_MS" ]]; then
                RETENTION_STR="${RETENTION_STR}[默认]"
            fi
        else
            # Fallback for topics without a specific or default retention.ms found.
            # It will use the pre-formatted default string from the stats command's initial setup.
            RETENTION_STR="${DEFAULT_RETENTION_STR}"
        fi
    
        echo "${size_formatted} ${topic} ${RETENTION_STR}"
    done
    ) | column -t
}

show_stats_help() {
    echo "用法: ${SCRIPT_NAME} stats [选项]"
    echo ""
    echo "显示集群的全面统计信息，包括 Zookeeper 状态、Broker 列表（含总日志大小和本机磁盘使用率）、Topic 磁盘占用 Top N 及其保留策略。"
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
    echo "用法: ${SCRIPT_NAME} retention {<topic名称> [选项] | --all}"
    echo ""
    echo "查看或修改 Topic 的数据保留时间。"
    echo ""
    echo "模式:"
    echo "  <topic名称>      操作单个 Topic。需要提供 Topic 名称。"
    echo "  --all            显示所有 Topic 的保留时间（自动显示查询进度）。"
    echo ""
    echo "选项:"
    echo "  --set <时间>   [单Topic模式] 设置新的数据保留时间。支持的单位: d(天), h(小时), min(分钟), ms(或纯数字)。"
    echo "  --delete       [单Topic模式] 删除自定义保留时间, 使用集群默认值。"
    echo "  -h, --help     显示此帮助信息。"
    echo ""
    echo "示例:"
    echo "  ${SCRIPT_NAME} retention --all                 # 查看所有 Topic 的保留时间"
    echo "  ${SCRIPT_NAME} retention my-topic              # 查看 'my-topic' 的保留时间"
    echo "  ${SCRIPT_NAME} retention my-topic --set 7d     # 将 'my-topic' 的保留时间设置为 7 天"
    echo "  ${SCRIPT_NAME} retention my-topic --delete     # 删除 'my-topic' 的自定义保留时间"
}

show_topic_help() {
    echo "用法: ${SCRIPT_NAME} topic <子命令> [选项]"
    echo ""
    echo "Topic 相关操作。"
    echo ""
    echo "可用子命令:"
    echo "  list           列出集群中所有的 Topic。"
    echo "  -h, --help     显示此帮助信息。"
    echo ""
    echo "示例:"
    echo "  ${SCRIPT_NAME} topic list"
}

show_isr_help() {
    echo "用法: ${SCRIPT_NAME} isr {<topic名称> | --all | --under-replicated-only}"
    echo ""
    echo "查询并显示 Topic 分区的 ISR (In-Sync Replicas) 状态。"
    echo "关键指标是 '状态' 一列，'UNDER-REPLICATED' 表示该分区的同步副本数少于总副本数，存在数据丢失风险，需要运维关注。"
    echo ""
    echo "模式:"
    echo "  <topic名称>               查询单个 Topic。"
    echo "  --all                     查询所有 Topic（自动显示查询进度）。"
    echo "  --under-replicated-only   仅显示状态为 'UNDER-REPLICATED' 的分区（自动查询所有 Topic）。"
    echo ""
    echo "选项:"
    echo "  -h, --help   显示此帮助信息。"
    echo ""
    echo "示例:"
    echo "  ${SCRIPT_NAME} isr my-topic                  # 查询单个 Topic 的 ISR 状态"
    echo "  ${SCRIPT_NAME} isr --all                     # 查询所有 Topic 的 ISR 状态"
    echo "  ${SCRIPT_NAME} isr --under-replicated-only   # 仅显示有问题的分区"
}

show_size_help() {
    echo "用法: ${SCRIPT_NAME} size {<topic名称> | --all | --top <N>}"
    echo ""
    echo "查询并显示 Topic 的磁盘占用大小。磁盘占用大小会根据实际大小自动选择合适的单位（M/G/T）显示。"
    echo ""
    echo "模式:"
    echo "  <topic名称>   查询单个 Topic 的磁盘占用。"
    echo "  --all         查询所有 Topic 的磁盘占用（自动显示统计进度，按大小降序排列）。"
    echo "  --top <N>     查询所有 Topic 并显示磁盘占用最大的前 N 个（自动按大小降序排列）。"
    echo ""
    echo "选项:"
    echo "  -h, --help   显示此帮助信息。"
    echo ""
    echo "示例:"
    echo "  ${SCRIPT_NAME} size my-topic   # 查询单个 Topic 的磁盘占用"
    echo "  ${SCRIPT_NAME} size --all      # 查询所有 Topic 的磁盘占用"
    echo "  ${SCRIPT_NAME} size --top 10   # 查询磁盘占用最大的前 10 个 Topic"
}

show_help() {
    echo "${SCRIPT_NAME} - 一个用于简化 Kafka 日常运维的命令行工具。"
    echo ""
    echo "用法: "
    echo "  ${SCRIPT_NAME} <命令> [选项...]"
    echo ""
    echo "可用命令:"
    echo "  init [show]  自动发现、持久化或显示 Kafka 环境配置 (首次使用必须运行 init)"
    echo "  retention    查看或修改指定 Topic 的数据保留时间"
    echo "  size         查询 Topic 的磁盘占用大小"
    echo "  isr          查询 Topic 分区的 ISR (In-Sync Replicas) 状态"
    echo "  stats        显示常用的集群统计信息 (ZK, Broker, 磁盘占用前N的topic、topic保留时间等)"
    echo "  topic        Topic 相关操作 (例如: list)"
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
        cmd_init "$@"
        ;;

    stats)
        cmd_stats "$@"
        ;;

    retention)
        cmd_retention "$@"
        ;;

    size)
        cmd_size "$@"
        ;;

    topic)
        cmd_topic "$@"
        ;;

    isr)
        cmd_isr "$@"
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