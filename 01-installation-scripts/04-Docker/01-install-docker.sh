#!/bin/bash

# docker-compose v2命令和v1不一样了，故使用老版本
# docker-compose >= 1.28 需要将 .env 拷贝到 compose 目录，目前 docker 官方尚未对此问题进行定义是否属于 bug ，使用 1.27 版本，可以避免此问题
docker_compose_version=1.27.4

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

# 脚本执行用户检测
if [[ $(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

# 检测操作系统
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2)
    # 阻止配置更新弹窗
    export UCF_FORCE_CONFFOLD=1
    # 阻止应用重启弹窗
    export NEEDRESTART_SUSPEND=1
elif [[ -e /etc/centos-release ]]; then
    os="centos"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/centos-release)
elif [[ -e /etc/rocky-release ]]; then
    os="rocky"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/rocky-release)
elif [[ -e /etc/almalinux-release ]]; then
    os="alma"
    os_version=$(grep -oE '([0-9]+\.[0-9]+(\.[0-9]+)?)' /etc/almalinux-release)
else
	echo_error 不支持的操作系统
	exit 99
fi

# 调docker配置
function adjust_docker_configuration() {
    echo_info docker配置调优
    mkdir -p /etc/docker
    cd /etc/docker
    cat > daemon.json << EOF
{
    "registry-mirrors": ["https://docker.1panel.live", "https://hub.rat.dev/", "https://docker.chenby.cn", "https://docker.m.daocloud.io"],
    "insecure-registries":["172.21.100.16:9998"],
    "data-root": "/data/docker",
    "log-opts": {"max-size":"10m", "max-file":"1"},
    "exec-opts": ["native.cgroupdriver=systemd"],
    "live-restore": true
}
EOF
    sleep 2
    systemctl daemon-reload
    systemctl stop docker
    systemctl start docker
    systemctl enable docker &> /dev/null

    echo_info docker已部署成功，版本信息如下：
    docker -v
}

function install_docker() {
    if [[ $os == 'centos' || $os == 'rocky' || $os == 'alma' ]];then
        echo_info 卸载之前安装的docker（如果有）
        yum remove docker \
            docker-client \
            docker-client-latest \
            docker-ce-cli \
            docker-common \
            docker-latest \
            docker-latest-logrotate \
            docker-logrotate \
            docker-engine \
            docker-ce
        rm -rf /var/lib/docker
        rm -rf /var/lib/containerd

        # 检测是否有wget工具
        if [ ! -f /usr/bin/wget ];then
            echo_info 安装wget工具
            yum install -y wget
        fi

        echo_info 使用yum安装docker
        cd /etc/yum.repos.d/
        [ -f docker-ce.repo ] || wget https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        yum makecache

        # 根据CentOS版本（7还是8）来进行安装
        if [[ $os == 'centos' ]];then
            osv=$(cat /etc/redhat-release | awk '{print $4}' | awk -F'.' '{print $1}')
            if [ $osv -eq 7 ]; then
                yum install docker-ce -y
            elif [ $osv -eq 8 ];then
                dnf install docker-ce --nobest -y
            else
                echo_error 当前版本不支持
                exit 1
            fi
        elif [[ $os == 'rocky' || $os == 'alma' ]];then
            dnf install -y docker-ce
        fi

        adjust_docker_configuration
        echo_warning 非root用户要使用docker命令的话，请执行命令：
        echo 'gpasswd -a 用户名 docker'
    elif [[ $os == 'ubuntu' ]];then
        echo_info 卸载之前安装的docker（如果有）
        for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get -y remove $pkg; done
        rm -rf /var/lib/docker
        rm -rf /var/lib/containerd

        echo_info 安装docker、docker-compose
        apt-get update -y
        apt-get install -y docker.io docker-compose

        adjust_docker_configuration
        echo_warning 非root用户要使用docker命令的话，请执行命令：
        echo 'gpasswd -a 用户名 docker'
    fi
}


function install_docker_compose() {
    echo_info 部署docker-compose中，请耐心等候

    # curl_timeout=4
    # # 设置dns超时时间，避免没网情况下等很久
    # echo "options timeout:${curl_timeout} attempts:1 rotate" >> /etc/resolv.conf
    # docker_compose_version=$(curl -s -H "User-Agent:Mozilla/5.0 (Macintosh; Intel Mac OS X 11_2_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.82 Safari/537.36" --connect-timeout ${curl_timeout} https://github.com/docker/compose/tags | grep "/docker/compose/releases/tag/" | head -1 | awk -F'"' '{print $2}' | xargs basename)
    # # 接口正常，[ ! ${docker_compose_version} ]为1；接口失败，[ ! ${docker_compose_version} ]为0
    # if [ ! ${docker_compose_version} ];then
    #     echo_error docker-compose github官网[ https://github.com/docker/compose/tags ]访问超时，请检查网络！
    #     sed -i '$d' /etc/resolv.conf
    #     exit 10
    # fi
    # sed -i '$d' /etc/resolv.conf

    back_task=/tmp/.display_dot_to_show_aliviness
    # 显示变化小点，表示没有卡死
    cat > $back_task << EOF
function echo_warning() {
    echo -e "[\033[36m\$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m\$@\033[0m"
}
cd /usr/local/bin
while :
do
    countx=\$(ls -l | grep -E "\sdocker-compose$" | awk '{print \$1}' | grep -o x | wc -l)
    if [ 3 -ne \$countx ];then
        printf "."
        sleep 1
    else 
        exit 0
    fi

    # 如果父进程消失了，表示用户手动取消，需要退出本脚本。head -1是必须的，不然会取到多个父shell pid
    fatherpid=\$(ps -ef | grep /tmp/.display_dot_to_show_aliviness | grep -v grep | awk '{print \$3}' | head -1)
    # 判断父进程ID是否等于1，如果是，表示父进程已经不存在了，因为1是init进程的ID，它是所有进程的祖先进程
    if [ 1 -eq \$fatherpid ];then
        exit 1
    fi
done
EOF

    /bin/bash $back_task &

    curl -sL --connect-timeout 5 "https://cors.isteed.cc/https://github.com/docker/compose/releases/download/${docker_compose_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo  # 换行，与小点隔开
    echo_info docker-compose已部署成功，版本信息如下：
    docker-compose --version
}

function install_docker_compose_confirm() {
    read -p "请输入数字进行选择：" user_input
    case ${user_input} in
        1)
            grep -nr "alias docker-compose" ~/.bashrc &> /dev/null
            if [ $? -ne 0 ];then
                echo_info 放弃安装docker-compose，将docker-compose命令指向docker compose命令
                echo 'alias docker-compose="docker compose"' >> ~/.bashrc
            fi
            ;;
        2)
            install_docker_compose
            ;;
        *)
            install_docker_compose_confirm
            ;;
    esac
}

function gen_show_container_ip_command() {
    cat > /usr/bin/show-container-ip << _EOF_
#!/bin/bash

# 带格式的echo函数
function echo_info() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m\$@\033[0m"
}
function echo_warning() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m\$@\033[0m"
}
function echo_error() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m\$@\033[0m"
}

print_help() {
    echo "使用方法: \$0 容器Name/ID"
}

# 脚本执行用户检测
if [[ \$(whoami) != 'root' ]];then
    echo_error 请使用root用户执行
    exit 99
fi

# 检查是否传入参数
if [ \$# -eq 0 ]; then
    echo_error "错误: 没有传入参数。"
    print_help
    exit 1
fi

# 检查参数是否正确
if [ \$# -gt 1 ]; then
    echo_error "错误: 只能传一个参数。"
    print_help
    exit 1
fi

# 检查容器是否正常运行
docker ps -a | grep \$1 &> /dev/null
if [ \$? -ne 0 ];then
    echo_error "未找到容器：\$1"
    exit 2
fi

docker ps -a | grep \$1 | grep "Exited" &> /dev/null
if [ \$? -eq 0 ];then
    echo_error "容器 \$1 已退出"
    exit 2
fi

# 检查nsenter命令
command -v nsenter &> /dev/null
if [ \$? -ne 0 ];then
    echo_info 安装nsenter
    yum install -y util-linux
fi

container_pid=\$(docker inspect -f {{.State.Pid}} \$1)
nsenter -n -t \$container_pid ip -4 addr show | grep inet | grep -v 127.0.0.1 | awk '{print \$2}' | cut -d/ -f1
_EOF_
chmod +x /usr/bin/show-container-ip
}

function gen_show_container_ip_command_confirm() {
    read -p "请输入数字进行选择：" user_input
    case ${user_input} in
        1)
            true
            ;;
        2)
            gen_show_container_ip_command
            ;;
        *)
            gen_show_container_ip_command_confirm
            ;;
    esac
}

################################ 安装 ##############
install_docker
if [[ $os == 'centos' || $os == 'rocky' || $os == 'alma' ]];then
    echo_warning "docker已自带compose插件，是否还单独安装docker-compose（${docker_compose_version}）?"
    echo [1] 不安装
    echo [2] 安装
    install_docker_compose_confirm
fi

echo_warning "是否生成查看容器ip的命令（/usr/bin/show-container-ip）?"
echo [1] 不生成
echo [2] 生成
gen_show_container_ip_command_confirm