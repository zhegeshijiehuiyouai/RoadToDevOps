#!/bin/bash
# 杀死各已知挖矿进程，单一般挖矿进程都有守护进程、母体这些，
# 需要手动查找清理，本脚本或许可以提供一些思路
ps auxf | grep -v grep | grep kinsing | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep kdevtmpfsi | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "mine.moneropool.com" awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "pool.t00ls.ru" | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "xmr.crypto-pool.fr" | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "zhuabcn@yahoo.com" | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "monerohash.com" | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "/tmp/a7b104c270" | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "stratum.f2pool.com" | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "xmrpool.eu" | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "minexmr.com" | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "xiaoyao" | awk '{print $2}' | xargs kill -9
ps auxf | grep -v grep | grep "xiaoxue" | awk '{print $2}' | xargs kill -9
ps auxf | grep var | grep lib | grep jenkins | grep -v httpPort | grep -v headless | grep "\-c" xargs kill -9
ps auxf | grep -v grep | grep "redis2" | awk '{print $2}' | xargs kill -9
pkill -f biosetjenkins
pkill -f Loopback
pkill -f apaceha
pkill -f cryptonight
pkill -f stratum
pkill -f performedl
pkill -f JnKihGjn
pkill -f irqba2anc1
pkill -f irqba5xnc1