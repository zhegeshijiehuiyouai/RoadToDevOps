FROM zhegeshijiehuiyouai/java:1.8

ENV MODE="standalone"

ADD nacos-server-1.1.3.tar.gz /usr/local/
ADD cluster.conf /usr/local/nacos/conf/
ADD entrypoint.sh /

EXPOSE 8848

ENTRYPOINT ["/entrypoint.sh"]
