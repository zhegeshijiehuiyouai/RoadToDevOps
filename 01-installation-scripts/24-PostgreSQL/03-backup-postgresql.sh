#!/bin/bash
source /etc/profile

PG_HOST=172.30.1.2
PG_PORT=5432
PG_USER=replica
PG_PASSWORD=noPassw0rd
BACK_DIR=/data/backup/postgresql
SUFFIX=$(date +%F)

[ -d ${BACK_DIR}/${SUFFIX} ] || mkdir -p ${BACK_DIR}/${SUFFIX}
cd ${BACK_DIR}

PGPASSWORD="${PG_PASSWORD}" pg_basebackup -h ${PG_HOST} -U ${PG_USER} -D ${BACK_DIR}/${SUFFIX} -Ft -z -Z5 -R -P -p ${PG_PORT}

find ./ -mtime +3 | xargs rm -rf