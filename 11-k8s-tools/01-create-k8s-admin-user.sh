#!/bin/bash
################################################################
# 功能：创建k8s集群管理员账号（自动检测版本，兼容旧版kubectl）
################################################################

# --- 配置区 ---
USER="k8sadmin" # 要创建的管理员用户名
CONFIG_PATH="${HOME}/.kube/config" # 当前有效的kubeconfig文件路径
NAMESPACE="kube-system"

# 带格式的echo函数
function echo_info() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32m信息\033[0m] \033[37m$@\033[0m"
}
function echo_warning() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33m警告\033[0m] \033[1;37m$@\033[0m"
}
function echo_error() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41m错误\033[0m] \033[1;31m$@\033[0m"
}

# 1. 从现有配置中提取集群信息
echo_info "正在从 ${CONFIG_PATH} 读取集群信息..."
CERT_AUTH_DATA=$(cat "$CONFIG_PATH" | grep "certificate-authority-data:" | awk '{print $2}' | head -n 1)
SERVER=$(cat "$CONFIG_PATH" | grep server | awk '{print $2}' | head -n 1)
CLUSTER_NAME=$(KUBECONFIG="$CONFIG_PATH" kubectl config view --minify -o jsonpath='{.clusters[0].name}')


# 2. 自动检测 Kubernetes 服务器版本
echo_info "正在自动检测 Kubernetes 服务器版本..."
SERVER_VERSION_LINE=$(kubectl --kubeconfig "$CONFIG_PATH" version | grep "Server Version:")
SERVER_MINOR_VERSION=$(echo "$SERVER_VERSION_LINE" | sed 's/.*v[0-9]*\.\([0-9]*\).*/\1/')

# 增加健壮性判断，如果获取失败则退出
if ! [[ "$SERVER_MINOR_VERSION" =~ ^[0-9]+$ ]]; then
    echo_error "无法获取有效的 Kubernetes 服务器次要版本号。请检查您的网络连接和权限。" >&2
    exit 1
fi

echo_info "检测到服务器次要版本为: ${SERVER_MINOR_VERSION}。"
# 根据版本号动态设置逻辑开关
if [ "$SERVER_MINOR_VERSION" -ge 24 ]; then
  CLUSTER_VERSION_EXCEED_V_12_4="yes"
else
  CLUSTER_VERSION_EXCEED_V_12_4="no"
fi

# 3. 根据版本判断结果，创建ServiceAccount和Secret以生成Token
if [ "$CLUSTER_VERSION_EXCEED_V_12_4" != "no" ]; then
  # 适用于 Kubernetes v1.24+ 的逻辑
  echo_info "版本大于等于 1.24，使用新方法生成 Token。"

  # 创建一个不含 secrets 字段的 ServiceAccount
  cat <<EOF >sa.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${USER}
  namespace: ${NAMESPACE}
EOF
  kubectl --kubeconfig $CONFIG_PATH apply -f sa.yaml &> /dev/null

  # 创建一个带注解的 Secret，让系统自动为其生成 Token
  cat <<EOF >secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ${USER}-token
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${USER}
type: kubernetes.io/service-account-token
EOF
  kubectl --kubeconfig $CONFIG_PATH apply -f secret.yaml &> /dev/null

  SECRET_NAME=${USER}-token
else
  # 适用于 Kubernetes v1.24 之前的旧逻辑
  echo_info "版本小于 1.24，使用旧方法生成 Token。"
  kubectl --kubeconfig $CONFIG_PATH create sa "${USER}" -n ${NAMESPACE} &> /dev/null
  # 获取 ServiceAccount 自动创建的 Secret 名称
  SECRET_NAME=$(kubectl --kubeconfig $CONFIG_PATH get sa "${USER}" -n ${NAMESPACE} -o go-template --template="{{range.secrets}}{{.name}}{{end}}")
fi

# 4. 为 ServiceAccount 授予集群管理员权限
echo_info "正在为 ServiceAccount ${USER} 绑定 cluster-admin 权限..."
# 检查绑定是否已存在，避免报错
if ! kubectl --kubeconfig "$CONFIG_PATH" get clusterrolebinding "${USER}-binding" &> /dev/null; then
    kubectl --kubeconfig $CONFIG_PATH create clusterrolebinding "${USER}-binding" --clusterrole=cluster-admin --serviceaccount=kube-system:"${USER}" &> /dev/null
fi

# 5. 提取生成的 Token
echo_info "正在从 Secret ${SECRET_NAME} 中提取 Token..."
TOKEN_ENCODING=$(kubectl --kubeconfig $CONFIG_PATH get secret "${SECRET_NAME}" -n ${NAMESPACE} -o go-template --template="{{.data.token}}")
TOKEN=$(echo "${TOKEN_ENCODING}" | base64 -d)

# 6. 生成并打印/保存全新的 kubeconfig 文件内容
OUTPUT_KUBECONFIG_PATH="${USER}-kubeconfig.yaml"
echo "======================= 新的 KUBECONFIG 内容 ======================="
(
echo "apiVersion: v1
kind: Config
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    server: ${SERVER}
    certificate-authority-data: ${CERT_AUTH_DATA}
contexts:
- name: ${CLUSTER_NAME}-${USER}-context-default
  context:
    cluster: ${CLUSTER_NAME}
    user: ${USER}
current-context: ${CLUSTER_NAME}-${USER}-context-default
users:
- name: ${USER}
  user:
    token: ${TOKEN}"
) | tee "${OUTPUT_KUBECONFIG_PATH}"
echo "=================================================================="

# 7. 清理临时文件
rm -f sa.yaml secret.yaml
echo_info "清理临时文件完成。"
echo_info "新的 kubeconfig 内容已打印在上方，并同时保存到了文件: ${PWD}/${OUTPUT_KUBECONFIG_PATH}"