#!/bin/bash

#获取setting.conf参数
cd /mnt/work/feely-sys
dubbo_addr=`grep dubbo setting.conf | cut -d= -f2`
nacos_addr=`grep nacos setting.conf | cut -d= -f2`
nacos_namespace=`grep namespace setting.conf | cut -d= -f2`
Xmx=`grep Xmx setting.conf | cut -d= -f2`
Xms=`grep Xms setting.conf | cut -d= -f2`
Xmn=`grep Xmn setting.conf | cut -d= -f2`


java -Xmx${Xmx} -Xms${Xms} -Xmn${Xmn} -XX:NewRatio=${NewRatio} -XX:NativeMemoryTracking=${NativeMemoryTracking} -XX:MaxDirectMemorySize=${MaxDirectMemorySize} -XX:SurvivorRatio=${SurvivorRatio} -XX:MetaspaceSize=${MetaspaceSize}  -XX:MaxMetaspaceSize=${MaxMetaspaceSize} -XX:MaxTenuringThreshold=${MaxTenuringThreshold} -XX:ParallelGCThreads=${ParallelGCThreads} -XX:ConcGCThreads=${ConcGCThreads} ${other} -XX:HeapDumpPath=${HeapDumpPath} -jar ${jar} ${log} ${other2} --dubbo.registry.address=${dubbo_addr} --spring.cloud.nacos.config.server-addr=${nacos_addr} --spring.cloud.nacos.config.namespace=${nacos_namespace}

