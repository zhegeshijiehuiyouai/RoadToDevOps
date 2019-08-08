#!/bin/bash
if [[ "${MODE}" == "standalone" ]]; then
    /usr/bin/sh /usr/local/nacos/bin/startup.sh -m standalone
elif [[ "${MODE}" == "cluster"  ]];then
    /usr/bin/sh /usr/local/nacos/bin/startup.sh
else
    echo "wrong MODE"
fi
tail -f /etc/hosts
