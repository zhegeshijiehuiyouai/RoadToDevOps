FROM centos:7.4.1708

ENV LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    LC_ALL=zh_CN.UTF-8

RUN yum update -y && \
    yum reinstall -y glibc-common && \
    yum install -y telnet net-tools && \
    yum install -y vim && \
    yum install -y epel-release && \
    yum clean all && \
    rm -rf /tmp/* rm -rf /var/cache/yum/* && \
    localedef -c -f UTF-8 -i zh_CN zh_CN.UTF-8 && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

CMD ["/bin/bash"]
