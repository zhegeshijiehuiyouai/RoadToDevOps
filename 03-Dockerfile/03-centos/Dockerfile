FROM centos:centos7.9.2009

ENV LC_ALL="en_US.utf8"

RUN yum install -y wget && \
    rm -rf /etc/yum.repos.d/* && \
    wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo && \
    wget -O /etc/yum.repos.d/epel.repo http://mirrors.aliyun.com/repo/epel-7.repo && \
    yum update -y && \
    yum install -y telnet net-tools vim && \
    yum clean all && \
    rm -rf /tmp/* rm -rf /var/cache/yum/* && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone

CMD ["/bin/bash"]