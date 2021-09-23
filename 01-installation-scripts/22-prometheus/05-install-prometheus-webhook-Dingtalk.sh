#!/bin/bash
# 将消息发到钉钉机器人

# 包下载目录
src_dir=$(pwd)/00src00
prometheus_webhook_dingtalk_port=8060
prometheus_webhook_dingtalk_version=1.4.0
# 部署prometheus_webhook_dingtalk的目录
prometheus_webhook_dingtalk_home=$(pwd)/prometheus_webhook_dingtalk-${prometheus_webhook_dingtalk_version}
sys_user=prometheus
unit_file_name=prometheus_webhook_dingtalk.service



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

# 解压
function untar_tgz(){
    echo_info 解压 $1 中
    tar xf $1
    if [ $? -ne 0 ];then
        echo_error 解压出错，请检查！
        exit 2
    fi
}

# 首先判断当前目录是否有压缩包：
#   I. 如果有压缩包，那么就在当前目录解压；
#   II.如果没有压缩包，那么就检查有没有 ${src_dir} 表示的目录;
#       1) 如果有目录，那么检查有没有压缩包
#           ① 有压缩包就解压
#           ② 没有压缩包则下载压缩包
#       2) 如果没有,那么就创建这个目录，然后 cd 到目录中，然后下载压缩包，然
#       后解压
# 解压的步骤都在后面，故此处只做下载

# 语法： download_tar_gz 保存的目录 下载链接
# 使用示例： download_tar_gz /data/openssh-update https://mirrors.cloud.tencent.com/openssl/source/openssl-1.1.1h.tar.gz
function download_tar_gz(){
    download_file_name=$(echo $2 |  awk -F"/" '{print $NF}')
    back_dir=$(pwd)
    file_in_the_dir=''  # 这个目录是后面编译目录的父目录

    ls $download_file_name &> /dev/null
    if [ $? -ne 0 ];then
        # 进入此处表示脚本所在目录没有压缩包
        ls -d $1 &> /dev/null
        if [ $? -ne 0 ];then
            # 进入此处表示没有${src_dir}目录
            mkdir -p $1 && cd $1
            echo_info 下载 $download_file_name 至 $(pwd)/
            # 检测是否有wget工具
            if [ ! -f /usr/bin/wget ];then
                echo_info 安装wget工具
                yum install -y wget
            fi
            wget $2
            if [ $? -ne 0 ];then
                echo_error 下载 $2 失败！
                exit 1
            fi
            file_in_the_dir=$(pwd)
            # 返回脚本所在目录，这样这个函数才可以多次使用
            cd ${back_dir}
        else
            # 进入此处表示有${src_dir}目录
            cd $1
            ls $download_file_name &> /dev/null
            if [ $? -ne 0 ];then
            # 进入此处表示${src_dir}目录内没有压缩包
                echo_info 下载 $download_file_name 至 $(pwd)/
                # 检测是否有wget工具
                if [ ! -f /usr/bin/wget ];then
                    echo_info 安装wget工具
                    yum install -y wget
                fi
                wget $2
                if [ $? -ne 0 ];then
                    echo_error 下载 $2 失败！
                    exit 1
                fi
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            else
                # 进入此处，表示${src_dir}目录内有压缩包
                echo_info 发现压缩包$(pwd)/$download_file_name
                file_in_the_dir=$(pwd)
                cd ${back_dir}
            fi
        fi
    else
        # 进入此处表示脚本所在目录有压缩包
        echo_info 发现压缩包$(pwd)/$download_file_name
        file_in_the_dir=$(pwd)
    fi
}

function add_user_and_group(){
    if id -g ${1} >/dev/null 2>&1; then
        echo_warning ${1}组已存在，无需创建
    else
        groupadd ${1}
        echo_info 创建${1}组
    fi
    if id -u ${1} >/dev/null 2>&1; then
        echo_warning ${1}用户已存在，无需创建
    else
        useradd -M -g ${1} -s /sbin/nologin ${1}
        echo_info 创建${1}用户
    fi
}

function is_run_prometheus_webhook_dingtalk() {
    ps -ef | grep ${prometheus_webhook_dingtalk_home} | grep -v grep &> /dev/null
    if [ $? -eq 0 ];then
        echo_error 检测到prometheus_webhook_dingtalk正在运行中，退出
        exit 3
    fi

    if [ -d ${prometheus_webhook_dingtalk_home} ];then
        echo_error 检测到目录${prometheus_webhook_dingtalk_home}，请检查是否重复安装，退出
        exit 4
    fi
}

function get_machine_ip() {
    ip a | grep -E "bond" &> /dev/null
    if [ $? -eq 0 ];then
        echo_warning 检测到绑定网卡（bond），请手动输入使用的 ip ：
        input_machine_ip_fun
    elif [ $(ip a | grep -E "inet.*e(ns|np|th).*[[:digit:]]+.*" | awk '{print $2}' | cut -d / -f 1 | wc -l) -gt 1 ];then
        echo_warning 检测到多个 ip，请手动输入使用的 ip ：
        input_machine_ip_fun
    else
        machine_ip=$(ip a | grep -E "inet.*e(ns|np|th).*[[:digit:]]+.*" | awk '{print $2}' | cut -d / -f 1)
    fi
}

function generate_config_sample() {
    get_machine_ip

    cd ${prometheus_webhook_dingtalk_home}
    echo_warning 生成配置文件${prometheus_webhook_dingtalk_home}/config.yml，记得钉钉机器人地址
    cp -a config.example.yml config.yml

    echo_info 生成定义模板，可在配置文件的templates项中指定
    cat > ${prometheus_webhook_dingtalk_home}/contrib/templates/default.tmpl << EOF
{{ define "__subject" }}[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .GroupLabels.SortedPairs.Values | join " " }} {{ if gt (len .CommonLabels) (len .GroupLabels) }}({{ with .CommonLabels.Remove .GroupLabels.Names }}{{ .Values | join " " }}{{ end }}){{ end }}{{ end }}
{{ define "__alertmanagerURL" }}{{ .ExternalURL }}/#/alerts?receiver={{ .Receiver }}{{ end }}

{{ define "__text_alert_list" }}{{ range . }}
**Labels**
{{ range .Labels.SortedPairs }}> - {{ .Name }}: {{ .Value | markdown | html }}
{{ end }}
**Annotations**
{{ range .Annotations.SortedPairs }}> - {{ .Name }}: {{ .Value | markdown | html }}
{{ end }}
**Source:** [{{ .GeneratorURL }}]({{ .GeneratorURL }})
{{ end }}{{ end }}

{{/* Firing */}}

{{ define "default.__text_alert_list" }}{{ range . }}

**Trigger Time:** {{ dateInZone "2006.01.02 15:04:05" (.StartsAt) "Asia/Shanghai" }}

**Summary:** {{ .Annotations.summary }}

**Description:** {{ .Annotations.description }}

**Graph:** [  ]({{ .GeneratorURL }})

**Details:**
{{ range .Labels.SortedPairs }}{{ if and (ne (.Name) "severity") (ne (.Name) "summary") }}> - {{ .Name }}: {{ .Value | markdown | html }}
{{ end }}{{ end }}
{{ end }}{{ end }}

{{/* Resolved */}}

{{ define "default.__text_resolved_list" }}{{ range . }}

**Trigger Time:** {{ dateInZone "2006.01.02 15:04:05" (.StartsAt) "Asia/Shanghai" }}

**Resolved Time:** {{ dateInZone "2006.01.02 15:04:05" (.EndsAt) "Asia/Shanghai" }}

**Summary:** {{ .Annotations.summary }}

**Graph:** [  ]({{ .GeneratorURL }})

**Details:**
{{ range .Labels.SortedPairs }}{{ if and (ne (.Name) "severity") (ne (.Name) "summary") }}> - {{ .Name }}: {{ .Value | markdown | html }}
{{ end }}{{ end }}
{{ end }}{{ end }}

{{/* Default */}}
{{ define "default.title" }}{{ template "__subject" . }}{{ end }}
{{ define "default.content" }}#### \[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}\] **[{{ index .GroupLabels "alertname" }}]({{ template "__alertmanagerURL" . }})**
{{ if gt (len .Alerts.Firing) 0 -}}

![Firing-img](https://is3-ssl.mzstatic.com/image/thumb/Purple20/v4/e0/23/cf/e023cf56-0623-0cdf-afce-97ae90eabfda/mzl.uplmrpgi.png/320x0w.jpg)

**Alerts Firing**
{{ template "default.__text_alert_list" .Alerts.Firing }}
{{- end }}
{{ if gt (len .Alerts.Resolved) 0 -}}

![Resolved-img](https://is3-ssl.mzstatic.com/image/thumb/Purple18/v4/41/72/99/4172990a-f666-badf-9726-6204a320c16e/mzl.dypdixoy.png/320x0w.png)

**Alerts Resolved**
{{ template "default.__text_resolved_list" .Alerts.Resolved }}
{{- end }}
{{- end }}

{{/* Legacy */}}
{{ define "legacy.title" }}{{ template "__subject" . }}{{ end }}
{{ define "legacy.content" }}#### \[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}\] **[{{ index .GroupLabels "alertname" }}]({{ template "__alertmanagerURL" . }})**
{{ template "__text_alert_list" .Alerts.Firing }}
{{- end }}

{{/* Following names for compatibility */}}
{{ define "ding.link.title" }}{{ template "default.title" . }}{{ end }}
{{ define "ding.link.content" }}{{ template "default.content" . }}{{ end }}
EOF

    echo_info 生成Alertmanager配置模板 ${prometheus_webhook_dingtalk_home}/alertmanager_templ.yml ，可参考来配置alertmanager
    cat > ${prometheus_webhook_dingtalk_home}/alertmanager_templ.yml <<EOF
global:
  resolve_timeout: 5m
  # smtp配置
  smtp_from: "1234567890@qq.com" # 发送邮件主题
  smtp_smarthost: 'smtp.qq.com:465' # 邮箱服务器的SMTP主机配置
  smtp_auth_username: "1234567890@qq.com" # 登录用户名
  smtp_auth_password: "auth_pass" # 此处的auth password是邮箱的第三方登录授权密码，而非用户密码，尽量用QQ来测试。
  smtp_require_tls: false # 有些邮箱需要开启此配置，这里使用的是163邮箱，仅做测试，不需要开启此功能。
route:
  receiver: ops
  group_wait: 30s # 在组内等待所配置的时间，如果同组内，30秒内出现相同报警，在一个组内出现。
  group_interval: 5m # 如果组内内容不变化，合并为一条警报信息，5m后发送。
  repeat_interval: 24h # 发送报警间隔，如果指定时间内没有修复，则重新发送报警。
  group_by: [alertname]  # 报警分组
  routes:
      - match:
          team: operations
        group_by: [env,dc]
        receiver: 'ops'
      - receiver: ops # 路由和标签，根据match来指定发送目标，如果 rule的lable 包含 alertname， 使用 ops 来发送
        group_wait: 10s
        match:
          team: operations
# 接收器指定发送人以及发送渠道
receivers:
# ops分组的定义
- name: ops
  # 邮件配置
  email_configs:
  - to: '9935226@qq.com,10000@qq.com'
    send_resolved: true
    headers: { Subject: "[operations] 报警邮件"} # 接收邮件的标题
  # 钉钉配置
  webhook_configs:
  - url: http://${machine_ip}:${prometheus_webhook_dingtalk_port}/dingtalk/ops/send # 这里是在钉钉开源组件中的接口，如果单独定义的receiver需要对应你的分组与钉钉机器人的webhook token
  # 企业微信配置
  wechat_configs:
  - corp_id: 'ww5421dksajhdasjkhj'
    api_url: 'https://qyapi.weixin.qq.com/cgi-bin/'
    send_resolved: true
    to_party: '2'
    agent_id: '1000002'
    api_secret: 'Tm1kkEE3RGqVhv5hO-khdakjsdkjsahjkdksahjkdsahkj'
# web
- name: web
  email_configs:
  - to: '9935226@qq.com'
    send_resolved: true
    headers: { Subject: "[web] 报警邮件"} # 接收邮件的标题
  webhook_configs:
  - url: http://${machine_ip}:${prometheus_webhook_dingtalk_port}/dingtalk/web/send
EOF
}

function generate_unit_file_and_start() {
    echo_info 生成${unit_file_name}文件用于systemd控制
    cat >/usr/lib/systemd/system/${unit_file_name} <<EOF
[Unit]
Description=prometheus-webhook-dingding
Documentation=https://prometheus.io/
After=network.target

[Service]
Type=simple
User=${sys_user}
Group=${sys_user}
ExecStart=${prometheus_webhook_dingtalk_home}/prometheus-webhook-dingtalk --web.listen-address=:${prometheus_webhook_dingtalk_port} --web.enable-ui --config.file=${prometheus_webhook_dingtalk_home}/config.yml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    echo_info ${prometheus_webhook_dingtalk_home} 目录授权
    chown -R ${sys_user}:${sys_user} ${prometheus_webhook_dingtalk_home}
    systemctl daemon-reload
    echo_info 启动prometheus_webhook_dingtalk
    systemctl start ${unit_file_name}
    if [ $? -ne 0 ];then
        echo_error prometheus_webhook_dingtalk启动失败，请检查
        exit 1
    fi
    systemctl enable ${unit_file_name} &> /dev/null

    generate_config_sample
    chown -R ${sys_user}:${sys_user} ${prometheus_webhook_dingtalk_home}

    echo_info prometheus_webhook_dingtalk已成功部署并启动，相关信息如下：
    echo -e "\033[37m                  启动命令：systemctl start ${unit_file_name}\033[0m"
    echo -e "\033[37m                  端口：${prometheus_webhook_dingtalk_port}\033[0m"
    echo -e "\033[37m                  部署目录：${prometheus_webhook_dingtalk_home}\033[0m"
}

function download_and_config() {
    https://github.com/timonwong/prometheus-webhook-dingtalk/releases/download/v1.4.0/prometheus-webhook-dingtalk-1.4.0.linux-amd64.tar.gz
    download_tar_gz ${src_dir}  https://github.com/timonwong/prometheus-webhook-dingtalk/releases/download/v${prometheus_webhook_dingtalk_version}/prometheus-webhook-dingtalk-${prometheus_webhook_dingtalk_version}.linux-amd64.tar.gz
    cd ${file_in_the_dir}
    untar_tgz prometheus-webhook-dingtalk-${prometheus_webhook_dingtalk_version}.linux-amd64.tar.gz
    mv prometheus-webhook-dingtalk-${prometheus_webhook_dingtalk_version}.linux-amd64 ${prometheus_webhook_dingtalk_home}

    add_user_and_group ${sys_user}

    generate_unit_file_and_start
}

function install_prometheus_webhook_dingtalk() {
    is_run_prometheus_webhook_dingtalk
    download_and_config
}

install_prometheus_webhook_dingtalk