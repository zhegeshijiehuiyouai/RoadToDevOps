FROM centos:centos7

USER root

ADD go1.17.linux-amd64.tar.gz /usr/local/
ADD cmake-3.6.0-Linux-x86_64.tar.gz /data
ADD gflags-2.2.2.tar.gz /data
ADD rocksdb-6.4.6.tar.gz /data
ADD zstd-1.1.3.tar.gz /data

RUN yum install -y gcc gcc-c++ lrzsz git lz4-devel snappy snappy-devel zlib zlib-devel bzip2 bzip2-devel lz4 lz4-devel && \
    cd /data && \
    yum remove cmake && \
    echo "export PATH=\$PATH:/data/cmake-3.6.0-Linux-x86_64/bin" >> /etc/profile && \
    source /etc/profile && \
    echo "export GOROOT=/usr/local/go" >> /etc/profile && \
    echo "export PATH=\$PATH:/usr/local/go/bin" >> /etc/profile && \
    source /etc/profile && \
    cd /data/gflags-2.2.2 && mkdir build && cd build && \
    cmake -DBUILD_SHARED_LIBS=ON -DBUILD_STATICaaa_LIBS=ON -DINSTALL_HEADERS=ON -DINSTALL_SHARED_LIBS=ON -DINSTALL_STATIC_LIBS=ON .. && \
    make -j 5 && make install && \
    echo "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/usr/local/lib" >> /etc/profile && \
    cd /data/zstd-1.1.3 && \
    make -j 5 && make install && \
    cd /data/rocksdb-6.4.6 && \
    make -j 5 static_lib && \
    make -j 5 shared_lib && \
    cp librocksdb.so.6.4.6 /usr/local/lib && \
    ln -s librocksdb.so.6.4.6 /usr/local/lib/librocksdb.so.6.4 && \
    ln -s librocksdb.so.6.4.6 /usr/local/lib/librocksdb.so.6 && \
    ln -s librocksdb.so.6.4.6 /usr/local/lib/librocksdb.so && \
    echo "export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/usr/local/lib" >> /etc/profile && \
    source /etc/profile

CMD tail -f /etc/hosts