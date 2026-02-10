#!/bin/bash

# 脚本配置 - 首次运行 init 后自动填充
KAFKA_HOME=""
KAFKA_MODE=""
ZK_CONNECT=""
BOOTSTRAP_SERVERS=""

# 全局配置
SCRIPT_NAME=$(basename "$0")
TOP_N=15
CLUSTER_DEFAULT_RETENTION_MS=""
CLUSTER_DEFAULT_RETENTION_SOURCE=""

check_config() {
    if [ -z "$KAFKA_HOME" ] || [ -z "$KAFKA_MODE" ]; then
        echo "错误: 脚本配置缺失。请先运行 './$(basename "$0") init' 来自动发现并持久化配置。" >&2
        exit 1
    fi
    
    if [ "$KAFKA_MODE" == "zk" ] && [ -z "$ZK_CONNECT" ]; then
        echo "错误: ZooKeeper 模式配置不完整，缺少 ZK_CONNECT。请重新运行 './$(basename "$0") init'。" >&2
        exit 1
    fi
    
    if [ "$KAFKA_MODE" == "kraft" ] && [ -z "$BOOTSTRAP_SERVERS" ]; then
        echo "错误: KRaft 模式配置不完整，缺少 BOOTSTRAP_SERVERS。请重新运行 './$(basename "$0") init'。" >&2
        exit 1
    fi
}

_get_cluster_default_retention() {
    if [ -n "$CLUSTER_DEFAULT_RETENTION_MS" ]; then
        return
    fi
    
    local ANY_BROKER_ID=""
    local BROKER_CONFIGS=""
    local DYNAMIC_SOURCE=""
    
    if [ "$KAFKA_MODE" == "zk" ]; then
        # 优先尝试读取 Broker 默认动态配置（Kafka 2.4+ 支持 --entity-default）
        BROKER_CONFIGS=$(_run_kafka_tool "kafka-configs.sh" --zookeeper ${ZK_CONNECT} --describe --entity-type brokers --entity-default 2>/dev/null)
        if [ -n "$BROKER_CONFIGS" ]; then
            DYNAMIC_SOURCE="(来自 Broker 默认动态配置)"
        fi

        # 回退：随机取一个 Broker ID 读取动态配置
        if [ -z "$BROKER_CONFIGS" ]; then
            ANY_BROKER_ID=$(_run_zk_cmd "${ZK_CONNECT}" "ls /brokers/ids" | sed -n 's/.*\[\([^]]*\)\].*/\1/p' | tr ',' ' ' | awk '{print $1}')
            if [ -n "$ANY_BROKER_ID" ]; then
                BROKER_CONFIGS=$(_run_kafka_tool "kafka-configs.sh" --zookeeper ${ZK_CONNECT} --describe --entity-type brokers --entity-name ${ANY_BROKER_ID} 2>/dev/null)
                DYNAMIC_SOURCE="(来自 Broker ${ANY_BROKER_ID} 动态配置)"
            fi
        fi
    elif [ "$KAFKA_MODE" == "kraft" ]; then
        BROKER_CONFIGS=$(_run_kafka_tool "kafka-configs.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --describe --entity-type brokers --entity-default 2>/dev/null)
        if [ -n "$BROKER_CONFIGS" ]; then
            DYNAMIC_SOURCE="(来自 Broker 默认动态配置)"
        fi

        # 回退：假设至少存在一个 broker
        if [ -z "$BROKER_CONFIGS" ]; then
            ANY_BROKER_ID="1"
            BROKER_CONFIGS=$(_run_kafka_tool "kafka-configs.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --describe --entity-type brokers --entity-name ${ANY_BROKER_ID} 2>/dev/null)
            if [ -n "$BROKER_CONFIGS" ]; then
                DYNAMIC_SOURCE="(来自 Broker ${ANY_BROKER_ID} 动态配置)"
            fi
        fi
    fi
    
    local RETENTION_MS=""
    local SOURCE=""
    local SOURCE_FROM_BROKER_CONFIGS="${DYNAMIC_SOURCE}"
    if [ -z "$SOURCE_FROM_BROKER_CONFIGS" ] && [ -n "$BROKER_CONFIGS" ]; then
        SOURCE_FROM_BROKER_CONFIGS="(来自 Broker 动态配置)"
    fi

    local VALUE=$(echo "${BROKER_CONFIGS}" | grep -oE 'log.retention.ms=-?[0-9]+' | head -n 1 | cut -d'=' -f2)
    if [[ -n "$VALUE" && "$VALUE" =~ ^-?[0-9]+$ ]]; then
        RETENTION_MS=${VALUE}
        SOURCE="${SOURCE_FROM_BROKER_CONFIGS}"
    fi
    
    if [ -z "$RETENTION_MS" ]; then
        VALUE=$(echo "${BROKER_CONFIGS}" | grep -oE 'log.retention.minutes=[0-9]+' | head -n 1 | cut -d'=' -f2)
        if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
            RETENTION_MS=$((VALUE * 60 * 1000))
            SOURCE="${SOURCE_FROM_BROKER_CONFIGS}"
        fi
    fi
    
    if [ -z "$RETENTION_MS" ]; then
        VALUE=$(echo "${BROKER_CONFIGS}" | grep -oE 'log.retention.hours=[0-9]+' | head -n 1 | cut -d'=' -f2)
        if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
            RETENTION_MS=$((VALUE * 60 * 60 * 1000))
            SOURCE="${SOURCE_FROM_BROKER_CONFIGS}"
        fi
    fi
    
    local CONFIG_FILE=""
    if [ "$KAFKA_MODE" == "zk" ]; then
        CONFIG_FILE="${KAFKA_HOME}/config/server.properties"
    elif [ "$KAFKA_MODE" == "kraft" ]; then
        CONFIG_FILE="${KAFKA_HOME}/config/kraft/server.properties"
        if [ ! -f "${CONFIG_FILE}" ]; then
            CONFIG_FILE="${KAFKA_HOME}/config/server.properties"
        fi
    fi
    
    if [[ -z "$RETENTION_MS" && -f "${CONFIG_FILE}" ]]; then
        VALUE=$(grep -E "^log.retention.ms=" ${CONFIG_FILE} | tail -n 1 | cut -d'=' -f2- | tr -d '[:space:]')
        if [[ -n "$VALUE" && "$VALUE" =~ ^-?[0-9]+$ ]]; then
            RETENTION_MS=${VALUE}
            SOURCE="(来自 server.properties)"
        fi
    
        if [ -z "$RETENTION_MS" ]; then
            VALUE=$(grep -E "^log.retention.minutes=" ${CONFIG_FILE} | tail -n 1 | cut -d'=' -f2- | tr -d '[:space:]')
            if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
                RETENTION_MS=$((VALUE * 60 * 1000))
                SOURCE="(来自 server.properties)"
            fi
        fi
    
        if [ -z "$RETENTION_MS" ]; then
            VALUE=$(grep -E "^log.retention.hours=" ${CONFIG_FILE} | tail -n 1 | cut -d'=' -f2- | tr -d '[:space:]')
            if [[ -n "$VALUE" && "$VALUE" =~ ^[0-9]+$ ]]; then
                RETENTION_MS=$((VALUE * 60 * 60 * 1000))
                SOURCE="(来自 server.properties)"
            fi
        fi
    fi
    
    if [ -z "$RETENTION_MS" ]; then
        RETENTION_MS=604800000
        SOURCE="(来自 Kafka 内置默认)"
    fi
    
    CLUSTER_DEFAULT_RETENTION_MS=${RETENTION_MS}
    CLUSTER_DEFAULT_RETENTION_SOURCE=${SOURCE}
}

discover_kafka_env() {
    echo "正在发现 Kafka 环境配置..."
    
    KAFKA_PROCESS_INFO=$(ps -ef | grep kafka.Kafka | grep -v grep)
    if [ -z "$KAFKA_PROCESS_INFO" ]; then
        echo "错误: 未找到正在运行的 Kafka Broker 进程" >&2
        exit 1
    fi

    local KAFKA_HOME_TEMP=""
    local KAFKA_SCRIPT_PATH=$(echo "$KAFKA_PROCESS_INFO" | grep -oE '/[^ ]+/bin/kafka-server-start.sh' | head -n 1)
    if [ -n "$KAFKA_SCRIPT_PATH" ]; then
        KAFKA_HOME_TEMP=$(dirname $(dirname "$KAFKA_SCRIPT_PATH"))
    else
        local KAFKA_LIBS_PATH=$(echo "$KAFKA_PROCESS_INFO" | grep -oE '/[^: ]+/libs/kafka_[^/]+\.jar' | head -n 1)
        if [ -n "$KAFKA_LIBS_PATH" ]; then
             KAFKA_HOME_TEMP=$(dirname $(dirname "$KAFKA_LIBS_PATH"))
        fi
    fi

    if [ -n "$KAFKA_HOME_TEMP" ]; then
        KAFKA_HOME_DISCOVERED=$(cd "$KAFKA_HOME_TEMP" && pwd)
    else
        echo "错误: 无法从 Kafka 进程信息中自动确定 KAFKA_HOME。" >&2
        echo "这可能是因为进程信息格式特殊。请尝试手动在脚本中配置 KAFKA_HOME。" >&2
        echo "原始进程信息: $KAFKA_PROCESS_INFO" >&2
        exit 1
    fi

    local CONFIG_FILE_PATH=""
    CONFIG_FILE_PATH=$(echo "$KAFKA_PROCESS_INFO" | grep -oP 'kafka\.Kafka\s+\K[^ ]+\.properties' | head -n 1)
    
    if [ -n "$CONFIG_FILE_PATH" ]; then
        if [[ ! "$CONFIG_FILE_PATH" = /* ]]; then
            CONFIG_FILE_PATH="${KAFKA_HOME_DISCOVERED}/${CONFIG_FILE_PATH}"
        fi
    fi
    
    if [ ! -f "$CONFIG_FILE_PATH" ]; then
        if [ -f "${KAFKA_HOME_DISCOVERED}/config/kraft/server.properties" ]; then
            CONFIG_FILE_PATH="${KAFKA_HOME_DISCOVERED}/config/kraft/server.properties"
        elif [ -f "${KAFKA_HOME_DISCOVERED}/config/server.properties" ]; then
            CONFIG_FILE_PATH="${KAFKA_HOME_DISCOVERED}/config/server.properties"
        else
            echo "错误: 无法找到 Kafka 配置文件" >&2
            exit 1
        fi
    fi
    
    local MODE_DISCOVERED=""
    local ZK_CONNECT_DISCOVERED=""
    local BOOTSTRAP_SERVERS_DISCOVERED=""
    
    if grep -qE "^process.roles=" "$CONFIG_FILE_PATH" && \
       grep -qE "^controller.quorum.voters=" "$CONFIG_FILE_PATH"; then
        MODE_DISCOVERED="kraft"
        local advertised_listener=$(grep -E "^advertised.listeners=" "$CONFIG_FILE_PATH" | cut -d'=' -f2 | tr -d '[:space:]')
        if [ -n "$advertised_listener" ]; then
            BOOTSTRAP_SERVERS_DISCOVERED=$(echo "$advertised_listener" | grep -oE '[A-Z0-9_]+://[^,]+' | head -n 1 | sed 's#^[A-Z0-9_]*://##')
        fi
        
        if [ -z "$BOOTSTRAP_SERVERS_DISCOVERED" ]; then
            local listener=$(grep -E "^listeners=" "$CONFIG_FILE_PATH" | cut -d'=' -f2 | tr -d '[:space:]')
            local first_listener=$(echo "$listener" | grep -oE '[A-Z0-9_]+://[^,]+' | head -n 1 | sed 's#^[A-Z0-9_]*://##')
            local listener_port=$(echo "$first_listener" | grep -oE ':[0-9]+$' | tr -d ':')
            if [ -n "$listener_port" ]; then
                local host_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
                [ -z "$host_ip" ] && host_ip="localhost"
                BOOTSTRAP_SERVERS_DISCOVERED="${host_ip}:${listener_port}"
            fi
        fi
        
        if [ -z "$BOOTSTRAP_SERVERS_DISCOVERED" ]; then
            echo "错误: KRaft 模式下无法确定 Bootstrap Servers 地址" >&2
            exit 1
        fi
        
    elif grep -qE "^zookeeper.connect=" "$CONFIG_FILE_PATH"; then
        MODE_DISCOVERED="zk"
        ZK_CONNECT_DISCOVERED=$(grep -E "^zookeeper.connect=" "$CONFIG_FILE_PATH" | cut -d'=' -f2 | tr -d '[:space:]')
        
        if [ -z "$ZK_CONNECT_DISCOVERED" ]; then
            echo "错误: 配置文件中未找到有效的 'zookeeper.connect' 配置" >&2
            exit 1
        fi

        # 尝试发现 Bootstrap Server (作为 ZK 工具失效时的兜底)
        local advertised_listener=$(grep -E "^advertised.listeners=" "$CONFIG_FILE_PATH" | cut -d'=' -f2 | tr -d '[:space:]')
        if [ -n "$advertised_listener" ]; then
            BOOTSTRAP_SERVERS_DISCOVERED=$(echo "$advertised_listener" | grep -oE '[A-Z0-9_]+://[^,]+' | head -n 1 | sed 's#^[A-Z0-9_]*://##')
        fi
        
        if [ -z "$BOOTSTRAP_SERVERS_DISCOVERED" ]; then
            local listener=$(grep -E "^listeners=" "$CONFIG_FILE_PATH" | cut -d'=' -f2 | tr -d '[:space:]')
            local first_listener=$(echo "$listener" | grep -oE '[A-Z0-9_]+://[^,]+' | head -n 1 | sed 's#^[A-Z0-9_]*://##')
            local listener_port=$(echo "$first_listener" | grep -oE ':[0-9]+$' | tr -d ':')
            if [ -n "$listener_port" ]; then
                local host_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
                [ -z "$host_ip" ] && host_ip="localhost"
                BOOTSTRAP_SERVERS_DISCOVERED="${host_ip}:${listener_port}"
            fi
        fi
        
    else
        echo "错误: 无法判断 Kafka 运行模式，配置文件: ${CONFIG_FILE_PATH}" >&2
        exit 1
    fi
    
    KAFKA_HOME=${KAFKA_HOME_DISCOVERED}
    KAFKA_MODE=${MODE_DISCOVERED}
    ZK_CONNECT=${ZK_CONNECT_DISCOVERED}
    BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS_DISCOVERED}
}

persist_config() {
    local script_path="$0"

    sed -i.bak \
        -e "s#^KAFKA_HOME=.*#KAFKA_HOME=\"${KAFKA_HOME}\"#" \
        -e "s#^KAFKA_MODE=.*#KAFKA_MODE=\"${KAFKA_MODE}\"#" \
        -e "s#^ZK_CONNECT=.*#ZK_CONNECT=\"${ZK_CONNECT}\"#" \
        -e "s#^BOOTSTRAP_SERVERS=.*#BOOTSTRAP_SERVERS=\"${BOOTSTRAP_SERVERS}\"#" \
        "${script_path}"

    if [ $? -eq 0 ]; then
        rm "${script_path}.bak"
    else
        echo "错误: 自动更新脚本配置失败。备份文件保留为 ${script_path}.bak" >&2
        exit 1
    fi
}

# 内部函数: 执行 ZK 命令
# 优先尝试使用 java 直接调用 org.apache.zookeeper.ZooKeeperMain，并限制堆内存为 256M
# 以解决直接调用 kafka 脚本可能因默认内存设置过大(如 3G)导致的 OOM 问题
_run_zk_cmd() {
    local zk_connect="$1"
    local zk_cmd="$2"
    
    # 方案 A: 直接 Java 调用 (轻量级)
    # 检查 java 命令是否存在以及 libs 目录是否存在
    if command -v java >/dev/null 2>&1 && [ -d "${KAFKA_HOME}/libs" ]; then
        local result
        # 捕获输出和错误 (ZooKeeperMain 的输出包括日志，均在 stderr/stdout)
        # 使用 256M 内存限制
        # 注意: classpath 通配符由 java 处理 (引号内)
        result=$(java -Xmx256M -cp "${KAFKA_HOME}/libs/*" org.apache.zookeeper.ZooKeeperMain -server "${zk_connect}" ${zk_cmd} 2>&1)
        local ret=$?
        
        # 检查关键错误标识，如果没有类加载错误，则认为尝试有效(即使 ZK 命令本身失败，也返回结果供上层解析)
        if [[ ! "$result" =~ "ClassNotFoundException" ]] && \
           [[ ! "$result" =~ "NoClassDefFoundError" ]] && \
           [[ ! "$result" =~ "Could not find or load main class" ]]; then
            echo "$result"
            return $ret
        fi
        # 如果 Java 调用失败 (如 classpath 不对)，则回退
    fi
    
    # 方案 B: 回退到原生脚本
    # 使用 echo 管道以保持最大的兼容性
    echo "${zk_cmd}" | ${KAFKA_HOME}/bin/zookeeper-shell.sh "${zk_connect}" 2>&1
}

# 内部函数: 执行 Kafka 工具命令 (优先使用低内存模式)
# 用法: _run_kafka_tool <script_name> <args...>
# 示例: _run_kafka_tool "kafka-log-dirs.sh" --bootstrap-server ...
_run_kafka_tool() {
    local script_name="$1"
    shift
    
    # 尝试直接使用 java
    if command -v java >/dev/null 2>&1 && [ -d "${KAFKA_HOME}/libs" ]; then
        local main_class=""
        case "$script_name" in
            "kafka-log-dirs.sh") main_class="kafka.admin.LogDirsCommand" ;;
            "kafka-topics.sh") main_class="kafka.admin.TopicCommand" ;;
            "kafka-configs.sh") main_class="kafka.admin.ConfigCommand" ;;
            "kafka-broker-api-versions.sh") main_class="kafka.admin.BrokerApiVersionsCommand" ;;
        esac
        
        if [ -n "$main_class" ]; then
            local result
            # 使用 256M 内存限制
            result=$(java -Xmx256M -cp "${KAFKA_HOME}/libs/*" ${main_class} "$@" 2>&1)
            local ret=$?
            
            # 宽松检查：只要没有严重的 Java 环境错误，就使用结果
            if [[ ! "$result" =~ "ClassNotFoundException" ]] && \
               [[ ! "$result" =~ "NoClassDefFoundError" ]] && \
               [[ ! "$result" =~ "Could not find or load main class" ]]; then
                echo "$result"
                return $ret
            fi
        fi
    fi
    
    # 回退到原始脚本
    ${KAFKA_HOME}/bin/${script_name} "$@" 2>&1
}

# 内部函数: 将时间字符串 (如 3d, 12h) 转换为毫秒
_parse_time_to_ms() {
    local time_str="$1"
    if [ "$time_str" == "-1" ]; then
        echo "-1"
        return 0
    fi

    local unit=$(echo "$time_str" | tr -d '0-9')
    local value=$(echo "$time_str" | tr -d 'a-zA-Z')
    unit=$(echo "$unit" | tr '[:upper:]' '[:lower:]')

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
        min|m)
            echo $((value * 60 * 1000))
            ;;
        ms|"") # 允许纯数字作为毫秒
            echo "$value"
            ;;
        *)
            echo "错误: 不支持的时间单位 '$unit'。请使用 d, h, m/min 或 ms，或使用 -1 表示无限保留。" >&2
            return 1
            ;;
    esac
}

# 内部函数: 格式化 retention.ms 为人类可读字符串
# -1 表示无限保留
_format_retention_ms() {
    local retention_ms="$1"

    if [[ -z "$retention_ms" || ! "$retention_ms" =~ ^-?[0-9]+$ ]]; then
        return 1
    fi

    if [ "$retention_ms" == "-1" ]; then
        echo "retention.ms=-1（无限）"
        return 0
    fi

    if [ "$retention_ms" -lt 0 ]; then
        return 1
    fi

    local retention_hours=$((retention_ms / 1000 / 60 / 60))
    echo "retention.ms=${retention_ms}（${retention_hours}小时）"
}

# 内部函数: 获取 Bootstrap Servers 列表
# 在 KRaft 模式下直接返回配置的值
# 在 ZK 模式下从 ZooKeeper 中发现所有 Broker 并构建列表
_get_bootstrap_servers() {
    if [ "$KAFKA_MODE" == "kraft" ]; then
        echo "$BOOTSTRAP_SERVERS"
    elif [ "$KAFKA_MODE" == "zk" ]; then
        # 从 ZooKeeper 中发现 Broker 列表
        local broker_ids_raw=""
        # 尝试使用 zookeeper-shell.sh，捕获标准输出和标准错误
        local zk_output
        zk_output=$(_run_zk_cmd "${ZK_CONNECT}" "ls /brokers/ids")
        local zk_exit_code=$?
        
        # 检查是否成功且无异常 (因为 zookeeper-shell 即使报错也可能返回 0，所以需检查 output 内容)
        if [ $zk_exit_code -eq 0 ] && [[ ! "$zk_output" =~ "Exception" ]] && [[ ! "$zk_output" =~ "Error" ]]; then
             broker_ids_raw=$(echo "$zk_output" | sed -n 's/.*\[\(.*\)\].*/\1/p')
        fi

        if [ -n "$broker_ids_raw" ]; then
            # ZK 方案成功
            local broker_ids=$(echo ${broker_ids_raw} | tr ',' ' ')
            local broker_endpoints_str=""
            for id in ${broker_ids}; do
                local endpoint=$(_run_zk_cmd "${ZK_CONNECT}" "get /brokers/ids/$id" | \
                    grep -oE '[A-Z0-9_]+://[^"]+' | head -n 1 | sed 's#^[A-Z0-9_]*://##')
                if [ -n "$endpoint" ]; then
                    broker_endpoints_str="${broker_endpoints_str}${endpoint},"
                fi
            done
            echo "${broker_endpoints_str%,}"
        else
            # ZK 方案失败，降级到 API 方案
            # 依赖 BOOTSTRAP_SERVERS 变量 (由 init 发现并保存)
            if [ -z "$BOOTSTRAP_SERVERS" ]; then
                echo "错误: ZooKeeper 工具不可用，且未配置 BOOTSTRAP_SERVERS。请重新运行 './${SCRIPT_NAME} init' 以更新配置。" >&2
                return 1
            fi
            
            # 使用 kafka-broker-api-versions.sh 获取所有节点地址
            local api_output
            api_output=$(_run_kafka_tool "kafka-broker-api-versions.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} 2>/dev/null)
            
            if [ -z "$api_output" ]; then
                echo "错误: 无法通过 ZooKeeper 发现 Broker，也无法连接到 Bootstrap Server ($BOOTSTRAP_SERVERS)。" >&2
                return 1
            fi

            # 解析输出格式: "host:port (id: 1 rack: null) -> ..."
            local endpoints=$(echo "$api_output" | grep -oE '^\S+:[0-9]+ \(id: [0-9]+' | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
            echo "$endpoints"
        fi
    else
        echo "错误: 未知的 Kafka 模式 '$KAFKA_MODE'。" >&2
        return 1
    fi
}

# 内部函数: 获取本机 Broker/Node ID（用于判断“本机磁盘使用率”应显示在哪一行）
_get_local_node_id() {
    local config_file=""
    local key=""

    if [ "$KAFKA_MODE" == "zk" ]; then
        config_file="${KAFKA_HOME}/config/server.properties"
        key="broker.id"
    elif [ "$KAFKA_MODE" == "kraft" ]; then
        config_file="${KAFKA_HOME}/config/kraft/server.properties"
        key="node.id"
        if [ ! -f "${config_file}" ]; then
            config_file="${KAFKA_HOME}/config/server.properties"
        fi
    else
        return 0
    fi

    if [ ! -f "${config_file}" ]; then
        return 0
    fi

    local value
    value=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${config_file}" 2>/dev/null | tail -n 1 | cut -d'=' -f2- | tr -d '[:space:]')
    if [[ -n "$value" && "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    fi
}

# 内部函数: 获取本机 IPv4 列表（空格分隔）
_get_local_ipv4_addrs() {
    local ips=""

    if command -v ip >/dev/null 2>&1; then
        ips=$(ip -4 -o addr show 2>/dev/null | awk '{print $4}' | cut -d'/' -f1 | tr '\n' ' ')
    fi

    if [ -z "$ips" ] && command -v hostname >/dev/null 2>&1; then
        ips=$(hostname -I 2>/dev/null | tr '\n' ' ')
    fi

    echo "$ips"
}

# 内部函数: 解析 endpoint（host:port 或 [ipv6]:port）里的 host
_endpoint_to_host() {
    local endpoint="$1"
    if [[ "$endpoint" =~ ^\\[([^\\]]+)\\]:(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "${endpoint%%:*}"
    fi
}

# 内部函数: 解析 host 的 IPv4（空格分隔）；若入参已是 IPv4 则原样返回
_resolve_ipv4_addrs() {
    local host="$1"
    if [[ -z "$host" ]]; then
        return 0
    fi

    if [[ "$host" =~ ^([0-9]{1,3}\\.){3}[0-9]{1,3}$ ]]; then
        echo "$host"
        return 0
    fi

    local ips=""

    if command -v getent >/dev/null 2>&1; then
        ips=$(getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | grep -E '^([0-9]{1,3}\\.){3}[0-9]{1,3}$' | sort -u | tr '\n' ' ')
        if [ -n "$ips" ]; then
            echo "$ips"
            return 0
        fi

        ips=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | grep -E '^([0-9]{1,3}\\.){3}[0-9]{1,3}$' | sort -u | tr '\n' ' ')
        if [ -n "$ips" ]; then
            echo "$ips"
            return 0
        fi
    fi

    if command -v dig >/dev/null 2>&1; then
        ips=$(dig +short A "$host" 2>/dev/null | grep -E '^([0-9]{1,3}\\.){3}[0-9]{1,3}$' | sort -u | tr '\n' ' ')
        if [ -n "$ips" ]; then
            echo "$ips"
            return 0
        fi
    fi

    if command -v host >/dev/null 2>&1; then
        ips=$(host -t A "$host" 2>/dev/null | awk '/has address/ {print $NF}' | sort -u | tr '\n' ' ')
        if [ -n "$ips" ]; then
            echo "$ips"
            return 0
        fi
    fi

    if command -v nslookup >/dev/null 2>&1; then
        ips=$(nslookup "$host" 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^([0-9]{1,3}\\.){3}[0-9]{1,3}$' | sort -u | tr '\n' ' ')
        if [ -n "$ips" ]; then
            echo "$ips"
            return 0
        fi
    fi
}

# 命令: retention
# 功能: 查看或修改 Topic 的数据保留时间
cmd_retention() {
    check_config

    # --- retention 命令参数解析 ---
    if [ "$1" == "--all" ]; then
        shift # consume --all

        _get_cluster_default_retention # 确保默认值已被加载

        local default_retention_str=""
        local default_retention_fmt
        default_retention_fmt=$(_format_retention_ms "$CLUSTER_DEFAULT_RETENTION_MS")
        if [ $? -eq 0 ]; then
            default_retention_str="${default_retention_fmt}[默认]"
            if [ "$CLUSTER_DEFAULT_RETENTION_MS" == "-1" ]; then
                echo "集群默认保留时间: 无限 (-1ms)${CLUSTER_DEFAULT_RETENTION_SOURCE}"
            else
                local default_hours=$((CLUSTER_DEFAULT_RETENTION_MS / 1000 / 60 / 60))
                echo "集群默认保留时间: ${default_hours}小时 (${CLUSTER_DEFAULT_RETENTION_MS}ms)${CLUSTER_DEFAULT_RETENTION_SOURCE}"
            fi
        else
            default_retention_str="retention.ms=无法获取默认值"
            echo "警告: 未能获取到集群默认日志保留时间。"
        fi
        
        local topics_list
        if [ "$KAFKA_MODE" == "zk" ]; then
            topics_list=$(_run_kafka_tool "kafka-topics.sh" --zookeeper ${ZK_CONNECT} --list | sort)
        elif [ "$KAFKA_MODE" == "kraft" ]; then
            topics_list=$(_run_kafka_tool "kafka-topics.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --list | sort)
        fi
        
        # 过滤掉空行再计数
        local total_topics
        total_topics=$(echo "$topics_list" | sed '/^$/d' | wc -l | tr -d ' ')

        if [ "$total_topics" -eq 0 ]; then
            echo "未发现任何 Topic"
            exit 0
        fi

        (
            echo "Topic名称|保留策略"
            local processed_count=0
            # 列出并排序所有 topic
            echo "$topics_list" | while read -r topic; do
                if [ -z "$topic" ]; then continue; fi

                processed_count=$((processed_count + 1))
                # 查询所有 topic 时默认显示进度
                local progress_str="查询进度: ${processed_count}/${total_topics} - ${topic}"
                printf "\r%-80s" "${progress_str}" >&2

                local topic_config
                if [ "$KAFKA_MODE" == "zk" ]; then
                    topic_config=$(_run_kafka_tool "kafka-configs.sh" --zookeeper ${ZK_CONNECT} --describe --entity-type topics --entity-name "${topic}" 2>/dev/null)
                elif [ "$KAFKA_MODE" == "kraft" ]; then
                    topic_config=$(_run_kafka_tool "kafka-configs.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --describe --entity-type topics --entity-name "${topic}" 2>/dev/null)
                fi
                local retention_ms=$(echo "${topic_config}" | tr ',' ' ' | awk -v key="retention.ms" 'BEGIN { prefix = key "=" } { for (i=1; i<=NF; i++) { if (substr($i, 1, length(prefix)) == prefix) { print substr($i, length(prefix) + 1); exit } } }')
                local retention_str=""

                local retention_fmt
                retention_fmt=$(_format_retention_ms "$retention_ms")
                if [ $? -eq 0 ]; then
                    retention_str="${retention_fmt}"
                    if [[ -n "$CLUSTER_DEFAULT_RETENTION_MS" && "$retention_ms" == "$CLUSTER_DEFAULT_RETENTION_MS" ]]; then
                        retention_str="${retention_str}[默认]"
                    fi
                else
                    retention_str="${default_retention_str}"
                fi
                echo "${topic}|${retention_str}"
            done
            
            # 清空进度条行，避免与输出混在一起
            printf "\r%-80s\r" "" >&2
        ) | _print_table_pipe
        
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
        if [ "$KAFKA_MODE" == "zk" ]; then
            _run_kafka_tool "kafka-configs.sh" --zookeeper ${ZK_CONNECT} --entity-type topics --entity-name "${topic_name}" \
                --alter --add-config retention.ms=${new_retention_ms} &>/dev/null
        elif [ "$KAFKA_MODE" == "kraft" ]; then
            _run_kafka_tool "kafka-configs.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --entity-type topics --entity-name "${topic_name}" \
                --alter --add-config retention.ms=${new_retention_ms} &>/dev/null
        fi
        
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
        if [ "$KAFKA_MODE" == "zk" ]; then
            output=$(_run_kafka_tool "kafka-configs.sh" --zookeeper ${ZK_CONNECT} --entity-type topics --entity-name "${topic_name}" \
                --alter --delete-config retention.ms 2>&1)
        elif [ "$KAFKA_MODE" == "kraft" ]; then
            output=$(_run_kafka_tool "kafka-configs.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --entity-type topics --entity-name "${topic_name}" \
                --alter --delete-config retention.ms 2>&1)
        fi
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
    local topic_config
    if [ "$KAFKA_MODE" == "zk" ]; then
        topic_config=$(_run_kafka_tool "kafka-configs.sh" --zookeeper ${ZK_CONNECT} --describe --entity-type topics --entity-name "${topic_name}" 2>/dev/null)
    elif [ "$KAFKA_MODE" == "kraft" ]; then
        topic_config=$(_run_kafka_tool "kafka-configs.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --describe --entity-type topics --entity-name "${topic_name}" 2>/dev/null)
    fi
    
    local retention_ms=$(echo "${topic_config}" | tr ',' ' ' | awk -v key="retention.ms" 'BEGIN { prefix = key "=" } { for (i=1; i<=NF; i++) { if (substr($i, 1, length(prefix)) == prefix) { print substr($i, length(prefix) + 1); exit } } }')
    local retention_str=""

    _get_cluster_default_retention # 确保默认值已被加载

    local retention_fmt
    retention_fmt=$(_format_retention_ms "$retention_ms")
    if [ $? -eq 0 ]; then
        retention_str="${retention_fmt}"
        if [[ "$retention_ms" == "$CLUSTER_DEFAULT_RETENTION_MS" ]]; then
            retention_str="${retention_str}[默认]"
        fi
    else
        local default_retention_fmt
        default_retention_fmt=$(_format_retention_ms "$CLUSTER_DEFAULT_RETENTION_MS")
        if [ $? -eq 0 ]; then
            retention_str="${default_retention_fmt}[默认]"
        else
            retention_str="retention.ms=无法获取默认值"
        fi
    fi
    
    # 模仿 stats 的输出格式以实现对齐
    (
      echo "Topic名称|保留策略"
      echo "${topic_name}|${retention_str}"
    ) | _print_table_pipe
}

# 命令: topic
# 功能: Topic 相关操作
cmd_topic() {
    check_config

    local sub_command="$1"
    shift || true

    case "$sub_command" in
        list)
            if [ "$KAFKA_MODE" == "zk" ]; then
                _run_kafka_tool "kafka-topics.sh" --zookeeper ${ZK_CONNECT} --list
            elif [ "$KAFKA_MODE" == "kraft" ]; then
                _run_kafka_tool "kafka-topics.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --list
            fi
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

            printf "%s|%s|%s|%s|%s|%s\n", topic, partition, leader, replicas, isr, status;
        }
    '

    # --- 逻辑执行 ---
    if ! $show_all; then
        local isr_output
        if [ "$KAFKA_MODE" == "zk" ]; then
            isr_output=$(_run_kafka_tool "kafka-topics.sh" --zookeeper ${ZK_CONNECT} --describe --topic "${topic_name}" 2>/dev/null | \
                awk -v under_replicated="${under_replicated_only}" "${awk_script}")
        elif [ "$KAFKA_MODE" == "kraft" ]; then
            isr_output=$(_run_kafka_tool "kafka-topics.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --describe --topic "${topic_name}" 2>/dev/null | \
                awk -v under_replicated="${under_replicated_only}" "${awk_script}")
        fi
        
        if [ -z "$isr_output" ]; then
            if [ "$under_replicated_only" = true ]; then
                echo "所有分区的 ISR 状态均正常。"
            fi
        else
            (
                echo "Topic|Partition|Leader|Replicas|Isr|Status"
                echo "$isr_output"
            ) | _print_table_pipe
        fi
    else
        local topics_list
        if [ "$KAFKA_MODE" == "zk" ]; then
            topics_list=$(_run_kafka_tool "kafka-topics.sh" --zookeeper ${ZK_CONNECT} --list | sort)
        elif [ "$KAFKA_MODE" == "kraft" ]; then
            topics_list=$(_run_kafka_tool "kafka-topics.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --list | sort)
        fi
        
        local total_topics
        total_topics=$(echo "$topics_list" | sed '/^$/d' | wc -l | tr -d ' ')

        if [ "$total_topics" -eq 0 ]; then
            echo "未发现任何 Topic"
            exit 0
        fi
        
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

                if [ "$KAFKA_MODE" == "zk" ]; then
                    _run_kafka_tool "kafka-topics.sh" --zookeeper ${ZK_CONNECT} --describe --topic "${topic}" 2>/dev/null | \
                        awk -v under_replicated="${under_replicated_only}" "${awk_script}"
                elif [ "$KAFKA_MODE" == "kraft" ]; then
                    _run_kafka_tool "kafka-topics.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --describe --topic "${topic}" 2>/dev/null | \
                        awk -v under_replicated="${under_replicated_only}" "${awk_script}"
                fi
            done
        ) > "$temp_output"
        
        # 清空进度条行
        printf "\r%-80s\r" "" >&2
        
        # 检查是否有数据
        if [ -s "$temp_output" ]; then
            (
                echo "Topic|Partition|Leader|Replicas|Isr|Status"
                cat "$temp_output"
            ) | _print_table_pipe
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
        echo "Kafka 配置信息:"
        echo "KAFKA_HOME: ${KAFKA_HOME}"
        echo "KAFKA_MODE: ${KAFKA_MODE}"
        if [ "$KAFKA_MODE" == "zk" ]; then
            echo "ZK_CONNECT: ${ZK_CONNECT}"
        elif [ "$KAFKA_MODE" == "kraft" ]; then
            echo "BOOTSTRAP_SERVERS: ${BOOTSTRAP_SERVERS}"
        fi
        exit 0
    fi
    discover_kafka_env
    persist_config
    echo ""
    echo "配置已保存:"
    echo "KAFKA_HOME: ${KAFKA_HOME}"
    echo "KAFKA_MODE: ${KAFKA_MODE}"
    if [ "$KAFKA_MODE" == "zk" ]; then
        echo "ZK_CONNECT: ${ZK_CONNECT}"
    elif [ "$KAFKA_MODE" == "kraft" ]; then
        echo "BOOTSTRAP_SERVERS: ${BOOTSTRAP_SERVERS}"
    fi
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

# 内部函数: 打印对齐表格（首行视为表头；字段分隔符为 |）
# 说明:
# - 统一全左对齐、列间距固定（2 个空格），不输出表头分隔线
# - 不做截断：字段过长时由终端自然换行（建议将易超长字段放在最后一列以减少视觉错位）
# - 依赖 util-linux 的 column；若不存在，则仅把分隔符替换为空格（不保证对齐）
_print_table_pipe() {
    if command -v column >/dev/null 2>&1; then
        column -t -s '|' -o '  '
        return
    fi

    if command -v sed >/dev/null 2>&1; then
        sed 's/|/  /g'
        return
    fi

    cat
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
    BROKER_LIST=$(_get_bootstrap_servers)
    if [ $? -ne 0 ] || [ -z "$BROKER_LIST" ]; then
        echo "错误: 未能获取 Broker 列表" >&2
        exit 1
    fi
    LOG_DIRS_DATA=$(_run_kafka_tool "kafka-log-dirs.sh" --bootstrap-server ${BROKER_LIST} --describe 2>/dev/null)

    if [ -z "$LOG_DIRS_DATA" ]; then
        echo "错误: 未能获取日志目录数据" >&2
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
        local size_bytes=${TOPIC_SIZES[$topic_name]}
        if [ -z "$size_bytes" ]; then
            echo "错误: Topic '${topic_name}' 不存在或没有数据。" >&2
            exit 1
        fi
        
        local size_formatted=$(_format_size "$size_bytes")
        
        (
            echo "磁盘占用|Topic名称"
            echo "${size_formatted}|${topic_name}"
        ) | _print_table_pipe
    else
        # 查询所有 topic
        local topics_list
        if [ "$KAFKA_MODE" == "zk" ]; then
            topics_list=$(_run_kafka_tool "kafka-topics.sh" --zookeeper ${ZK_CONNECT} --list | sort)
        elif [ "$KAFKA_MODE" == "kraft" ]; then
            topics_list=$(_run_kafka_tool "kafka-topics.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --list | sort)
        fi
        
        local total_topics
        total_topics=$(echo "$topics_list" | sed '/^$/d' | wc -l | tr -d ' ')

        if [ "$total_topics" -eq 0 ]; then
            echo "未发现任何 Topic"
            exit 0
        fi

        local display_count=${top_n:-$total_topics}
        
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
            echo "磁盘占用|Topic名称"
            # 按字节数排序（数值排序，降序），然后格式化显示
            sort -rn "$temp_output" | head -n ${display_count} | while read -r bytes topic; do
                local formatted_size=$(_format_size "$bytes")
                echo "${formatted_size}|${topic}"
            done
        ) | _print_table_pipe
        
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

    # 步骤 1: 显示集群模式信息
    local zk_server_list=""
    if [ "$KAFKA_MODE" == "zk" ]; then
        echo "【ZooKeeper 模式】"
        
        # 从 ZK_CONNECT 中提取服务器列表, 移除可能存在的 chroot 路径
        local zk_servers_with_chroot=$(echo "$ZK_CONNECT" | cut -d'/' -f1)
        # 将逗号替换为空格, 以便在 for 循环中迭代
        zk_server_list=$(echo "$zk_servers_with_chroot" | tr ',' ' ')
        
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
                local output_data="Zookeeper节点|角色|备注\n"

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
                    output_data+="${server_full_names[j]}|${server_modes[j]}|${note}\n"
                done

                printf "%b" "${output_data}" | _print_table_pipe
                
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
    elif [ "$KAFKA_MODE" == "kraft" ]; then
        echo "【KRaft 模式】Bootstrap Servers: ${BOOTSTRAP_SERVERS}"
        echo ""
    fi

    # 获取 Broker 列表（适配两种模式）
    BROKER_LIST=$(_get_bootstrap_servers)
    if [ $? -ne 0 ] || [ -z "$BROKER_LIST" ]; then
        echo "错误: 未能获取 Broker 列表"
        exit 1
    fi
    
    # 获取 Broker IDs（用于后续显示）
    if [ "$KAFKA_MODE" == "zk" ]; then
        # 尝试使用 ZK
        local zk_output
        zk_output=$(_run_zk_cmd "${ZK_CONNECT}" "ls /brokers/ids")
        local zk_exit_code=$?
        
        if [ $zk_exit_code -eq 0 ] && [[ ! "$zk_output" =~ "Exception" ]] && [[ ! "$zk_output" =~ "Error" ]]; then
            BROKER_IDS_RAW=$(echo "$zk_output" | sed -n 's/.*\[\(.*\)\].*/\1/p')
            BROKER_IDS=$(echo ${BROKER_IDS_RAW} | tr ',' ' ')
        fi
        
        # 如果 ZK 失败，尝试使用 API
        if [ -z "$BROKER_IDS" ]; then
            if [ -n "$BOOTSTRAP_SERVERS" ]; then
                 BROKER_IDS=$(_run_kafka_tool "kafka-broker-api-versions.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} 2>/dev/null | grep -oE '^\S+:[0-9]+ \(id: [0-9]+' | sed 's/.*(id: \([0-9]*\).*/\1/' | sort -u)
            fi
        fi

        if [ -z "$BROKER_IDS" ]; then
            echo "错误: 无法获取 Broker ID 列表 (ZK 和 API 均失败)" >&2
            exit 1
        fi
    elif [ "$KAFKA_MODE" == "kraft" ]; then
        # KRaft 模式下，从 kafka-broker-api-versions 命令获取 broker 列表
        BROKER_IDS=$(_run_kafka_tool "kafka-broker-api-versions.sh" --bootstrap-server ${BROKER_LIST} 2>/dev/null | grep -oE '^\S+:[0-9]+ \(id: [0-9]+' | sed 's/.*(id: \([0-9]*\).*/\1/' | sort -u)
        if [ -z "$BROKER_IDS" ]; then
            # 备用方案：假设至少有一个broker
            BROKER_IDS="1"
        fi
    fi

    LOG_DIRS_DATA=$(_run_kafka_tool "kafka-log-dirs.sh" --bootstrap-server ${BROKER_LIST} --describe 2>/dev/null)
    
    declare -A BROKER_SIZES
    declare -A BROKER_LOG_DIRS
    declare -A BROKER_VOLUME_TOTAL_BYTES
    declare -A BROKER_VOLUME_USABLE_BYTES
    declare -A BROKER_VOLUME_REF_DIR
    
    # 使用 AWK 解析 JSON 输出, 汇总每个 Broker 的总大小和 Log 目录
    # 使用进程替换 < <(...) 来避免在 subshell 中运行 while 循环, 确保数组变量在循环外可用
    while IFS=$'\t' read -r id size_bytes dirs vol_total_bytes vol_usable_bytes vol_ref_dir; do
        BROKER_SIZES[$id]=$size_bytes
        BROKER_LOG_DIRS[$id]=$dirs
        BROKER_VOLUME_TOTAL_BYTES[$id]=$vol_total_bytes
        BROKER_VOLUME_USABLE_BYTES[$id]=$vol_usable_bytes
        BROKER_VOLUME_REF_DIR[$id]=$vol_ref_dir
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
        first_log_dir = "";
        while (match(record_for_dirs, /"logDir":"([^"]+)"/)) {
            dir = substr(record_for_dirs, RSTART+10, RLENGTH-11);
            if (first_log_dir == "") {
                first_log_dir = dir;
            }
            dirs[dir] = 1;
            record_for_dirs = substr(record_for_dirs, RSTART+RLENGTH);
        }

        total_bytes = -1;
        usable_bytes = -1;

        record_for_vol = $0;
        if (match(record_for_vol, /"totalBytes":-?[0-9]+/)) {
            v = substr(record_for_vol, RSTART, RLENGTH);
            sub(/"totalBytes":/, "", v);
            total_bytes = v;
        } else if (match(record_for_vol, /"total_bytes":-?[0-9]+/)) {
            v = substr(record_for_vol, RSTART, RLENGTH);
            sub(/"total_bytes":/, "", v);
            total_bytes = v;
        }

        record_for_vol = $0;
        if (match(record_for_vol, /"usableBytes":-?[0-9]+/)) {
            v = substr(record_for_vol, RSTART, RLENGTH);
            sub(/"usableBytes":/, "", v);
            usable_bytes = v;
        } else if (match(record_for_vol, /"usable_bytes":-?[0-9]+/)) {
            v = substr(record_for_vol, RSTART, RLENGTH);
            sub(/"usable_bytes":/, "", v);
            usable_bytes = v;
        }

        dir_list = "";
        for (d in dirs) {
            dir_list = (dir_list == "" ? d : dir_list "," d);
        }
        
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", broker_id, total_size, dir_list, total_bytes, usable_bytes, first_log_dir
    }')

    local local_node_id
    local_node_id=$(_get_local_node_id)

    local local_ipv4s
    local_ipv4s=$(_get_local_ipv4_addrs)
    if [ -z "$local_ipv4s" ] && command -v ip >/dev/null 2>&1; then
        local_ipv4s=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | tr '\n' ' ')
    fi

    declare -A local_ipv4_set
    for ip in $local_ipv4s; do
        local_ipv4_set["$ip"]=1
    done

    local id_column_name="BrokerID"
    if [ "$KAFKA_MODE" == "kraft" ]; then
        id_column_name="NodeID"
    fi

    # 预先获取 API 版本的 Endpoint 映射 (用于 ZK 降级或 KRaft 模式)
    declare -A API_ENDPOINTS_MAP
    if [ "$KAFKA_MODE" == "kraft" ] || [ -z "$BROKER_IDS_RAW" ]; then
        # 如果是 KRaft 模式，或者 ZK 获取 ID 失败（意味着 ZK 不可用），则加载 API 数据
        local api_data
        api_data=$(_run_kafka_tool "kafka-broker-api-versions.sh" --bootstrap-server ${BROKER_LIST} 2>/dev/null | grep -oE '^\S+:[0-9]+ \(id: [0-9]+')
        while read -r line; do
             # line 格式: host:port (id: 1
             local ep=$(echo "$line" | awk '{print $1}')
             local bid=$(echo "$line" | grep -oE 'id: [0-9]+' | awk '{print $2}')
             if [ -n "$bid" ]; then
                 API_ENDPOINTS_MAP[$bid]=$ep
             fi
        done <<< "$api_data"
    fi

    (
        echo "${id_column_name}|Endpoint|总日志大小|日志盘使用率"
        for id in ${BROKER_IDS}; do
            local endpoint=""
            if [ "$KAFKA_MODE" == "zk" ]; then
                # 尝试 ZK
                if [ -n "$BROKER_IDS_RAW" ]; then # 只有当 ZK 之前成功获取了 ID 列表时才尝试用 ZK 获取 endpoint
                    endpoint=$(_run_zk_cmd "${ZK_CONNECT}" "get /brokers/ids/$id" | \
                        grep -oE '[A-Z0-9_]+://[^"]+' | head -n 1 | sed 's#^[A-Z0-9_]*://##')
                fi
                
                # 降级：如果 ZK 没获取到，查 API 缓存
                if [ -z "$endpoint" ]; then
                    endpoint=${API_ENDPOINTS_MAP[$id]}
                fi
            elif [ "$KAFKA_MODE" == "kraft" ]; then
                # KRaft 模式下，优先查 API 缓存
                endpoint=${API_ENDPOINTS_MAP[$id]}
                if [ -z "$endpoint" ]; then
                    # 如果无法获取，使用 BOOTSTRAP_SERVERS
                    endpoint=${BOOTSTRAP_SERVERS}
                fi
            fi
            if [ -n "$endpoint" ]; then
                size_bytes=${BROKER_SIZES[$id]:-0}
                log_dirs=${BROKER_LOG_DIRS[$id]}
                size_formatted=$(_format_size "$size_bytes")
                
                disk_usage="--"
                local vol_total_bytes=${BROKER_VOLUME_TOTAL_BYTES[$id]:--1}
                local vol_usable_bytes=${BROKER_VOLUME_USABLE_BYTES[$id]:--1}
                local vol_ref_dir=${BROKER_VOLUME_REF_DIR[$id]}

                # 优先使用 Kafka 返回的磁盘信息（若 kafka-log-dirs 输出中包含 totalBytes/usableBytes）
                if [[ "$vol_total_bytes" =~ ^[0-9]+$ && "$vol_total_bytes" -gt 0 && "$vol_usable_bytes" =~ ^[0-9]+$ && "$vol_usable_bytes" -ge 0 ]]; then
                    local vol_used_bytes
                    vol_used_bytes=$((vol_total_bytes - vol_usable_bytes))
                    if [ "$vol_used_bytes" -lt 0 ]; then
                        vol_used_bytes=0
                    fi
                    local pcent
                    pcent=$(awk -v used="$vol_used_bytes" -v total="$vol_total_bytes" 'BEGIN { if (total <= 0) { print "" } else { printf "%.0f", (used/total)*100 } }')
                    disk_usage="${pcent}% [$(_format_size "$vol_used_bytes")/$(_format_size "$vol_total_bytes")] ${vol_ref_dir}"
                else
                    local is_local=0
                    if [[ -n "$local_node_id" && "$id" == "$local_node_id" ]]; then
                        is_local=1
                    else
                        local broker_host
                        broker_host=$(_endpoint_to_host "$endpoint")
                        local broker_ipv4s
                        broker_ipv4s=$(_resolve_ipv4_addrs "$broker_host")
                        for ip in $broker_ipv4s; do
                            if [[ -n "${local_ipv4_set[$ip]}" ]]; then
                                is_local=1
                                break
                            fi
                        done
                    fi

                    # 回退: 仅对本机 broker 用 df 计算
                    if [[ -n "$log_dirs" && "$is_local" -eq 1 ]]; then
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
                fi

                echo "$id|$endpoint|$size_formatted|$disk_usage"
            fi
        done
    ) | _print_table_pipe
    echo ""

    # 获取集群默认保留时间
    _get_cluster_default_retention # 调用新的公共函数
    
    DEFAULT_RETENTION_STR=""
    local default_retention_fmt
    default_retention_fmt=$(_format_retention_ms "$CLUSTER_DEFAULT_RETENTION_MS")
    if [ $? -eq 0 ]; then
        DEFAULT_RETENTION_STR="${default_retention_fmt}[默认]"
        if [ "$CLUSTER_DEFAULT_RETENTION_MS" == "-1" ]; then
            echo "集群默认保留时间: 无限 (-1ms)${CLUSTER_DEFAULT_RETENTION_SOURCE}"
        else
            DEFAULT_RETENTION_HOURS=$((CLUSTER_DEFAULT_RETENTION_MS / 1000 / 60 / 60))
            echo "集群默认保留时间: ${DEFAULT_RETENTION_HOURS}小时 (${CLUSTER_DEFAULT_RETENTION_MS}ms)${CLUSTER_DEFAULT_RETENTION_SOURCE}"
        fi
    else
        DEFAULT_RETENTION_STR="retention.ms=无法获取默认值"
    fi
    echo ""
    
    echo "Top ${current_top_n} Topic 磁盘占用:"
    
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
    echo "磁盘占用|Topic名称|保留策略"
    
    echo "$TOP_TOPICS_DATA" | while read -r size_bytes topic; do
        # 格式化大小显示
        size_formatted=$(_format_size "$size_bytes")
        
        local RETENTION_MS
        if [ "$KAFKA_MODE" == "zk" ]; then
            RETENTION_MS=$(_run_kafka_tool "kafka-configs.sh" --zookeeper ${ZK_CONNECT} --describe --entity-type topics --entity-name ${topic} 2>/dev/null | \
                tr ',' ' ' | awk -v key="retention.ms" 'BEGIN { prefix = key "=" } { for (i=1; i<=NF; i++) { if (substr($i, 1, length(prefix)) == prefix) { print substr($i, length(prefix) + 1); exit } } }')
        elif [ "$KAFKA_MODE" == "kraft" ]; then
            RETENTION_MS=$(_run_kafka_tool "kafka-configs.sh" --bootstrap-server ${BOOTSTRAP_SERVERS} --describe --entity-type topics --entity-name ${topic} 2>/dev/null | \
                tr ',' ' ' | awk -v key="retention.ms" 'BEGIN { prefix = key "=" } { for (i=1; i<=NF; i++) { if (substr($i, 1, length(prefix)) == prefix) { print substr($i, length(prefix) + 1); exit } } }')
        fi
    
        local RETENTION_STR=""
        local retention_fmt
        retention_fmt=$(_format_retention_ms "$RETENTION_MS")
        if [ $? -eq 0 ]; then
            RETENTION_STR="${retention_fmt}"
            if [[ "$RETENTION_MS" == "$CLUSTER_DEFAULT_RETENTION_MS" ]]; then
                RETENTION_STR="${RETENTION_STR}[默认]"
            fi
        else
            # Fallback for topics without a specific or default retention.ms found.
            # It will use the pre-formatted default string from the stats command's initial setup.
            RETENTION_STR="${DEFAULT_RETENTION_STR}"
        fi
    
        echo "${size_formatted}|${topic}|${RETENTION_STR}"
    done
    ) | _print_table_pipe
}

show_stats_help() {
    echo "用法: ${SCRIPT_NAME} stats [选项]"
    echo ""
    echo "显示集群的全面统计信息，包括 Zookeeper 状态、Broker 列表（含总日志大小和日志盘使用率）、Topic 磁盘占用 Top N 及其保留策略。"
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
    echo "  --set <时间>   [单Topic模式] 设置新的数据保留时间。支持的单位: d(天), h(小时), m/min(分钟), ms(或纯数字)；也支持 -1 表示无限保留。"
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
    echo "${SCRIPT_NAME} - 一个用于简化 Kafka 日常运维的命令行工具"
    echo ""
    echo "用法: ${SCRIPT_NAME} <命令> [选项...]"
    echo ""
    echo "可用命令:"
    echo "  init [show]  自动发现并保存 Kafka 环境配置 (首次使用必须运行)"
    echo "  retention    查看或修改指定 Topic 的数据保留时间"
    echo "  size         查询 Topic 的磁盘占用大小"
    echo "  isr          查询 Topic 分区的 ISR 状态"
    echo "  stats        显示集群统计信息 (Broker、磁盘占用、保留时间等)"
    echo "  topic        Topic 相关操作 (例如: list)"
    echo "  help         显示此帮助信息"
    echo ""
}

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
