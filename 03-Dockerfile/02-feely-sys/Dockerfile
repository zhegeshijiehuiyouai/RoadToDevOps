FROM zhegeshijiehuiyouai/java:1.8

#other是所有没有等号的参数，other2是为了以后扩展用的
ENV NewRatio=4 NativeMemoryTracking=detail MaxDirectMemorySize=256m SurvivorRatio=8 \
    MetaspaceSize=256m MaxMetaspaceSize=512m MaxTenuringThreshold=15 ParallelGCThreads=8 ConcGCThreads=8 \
    HeapDumpPath="dump/error.dump" jar="/mnt/work/feely-sys/sys-uc.jar" log="--logging.file=/mnt/work/feely-sys/log/feely-sys.log" \
    other="-XX:+UseG1GC -XX:+DisableExplicitGC -XX:+HeapDumpOnOutOfMemoryError" other2=""

ADD sys-uc.jar /mnt/work/feely-sys/
ADD setting.conf /mnt/work/feely-sys/
ADD entrypoint.sh /

EXPOSE 8801

ENTRYPOINT ["/entrypoint.sh"]
