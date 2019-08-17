FROM centos:7.4.1708

ENV LC_ALL="en_US.utf8"

RUN yum update -y && \
    yum install -y telnet net-tools && \
    yum install -y vim && \
    yum install -y epel-release && \
    yum clean all && \
    rm -rf /tmp/* rm -rf /var/cache/yum/* && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

CMD ["/bin/bash"]