#!/bin/bash
# 功能：清空数据盘，删除所有数据盘的分区和 fstab 中对应的条目

# 获取所有非vda的物理磁盘
disks=$(lsblk | egrep -v ".da|nvme0" | grep disk | awk '{print $1}')

echo "检测到以下磁盘将被清空："
echo "$disks"
echo "警告：此操作将删除这些磁盘上的所有数据！"
echo "请确认是否继续？(y/n)"
read confirm

if [ "$confirm" != "y" ]; then
    echo "操作已取消"
    exit 1
fi

# 卸载所有要处理的磁盘
for disk in $disks; do
    mount_points=$(lsblk -n -o MOUNTPOINT /dev/${disk} | grep -v '^$')
    if [ ! -z "$mount_points" ]; then
        echo "正在卸载 /dev/${disk} 的所有挂载点"
        echo "$mount_points" | while read mount_point; do
            umount "$mount_point" && echo "已卸载 $mount_point" || echo "卸载 $mount_point 失败"
        done
    fi
done

# 备份并清理 fstab
echo "正在备份 /etc/fstab 到 /etc/fstab.backup"
cp /etc/fstab /etc/fstab.backup

for disk in $disks; do
    echo "正在从 /etc/fstab 中移除 /dev/${disk} 的相关条目"
    sed -i "\|^/dev/${disk}|d" /etc/fstab
    # 获取磁盘 UUID 并从 fstab 中删除
    disk_uuids=$(blkid | grep /dev/${disk}.* | awk -F '"' '{print $2}')
    for disk_uuid in disk_uuids;do
        if [ ! -z "$disk_uuid" ]; then
            echo "检测到UUID: $disk_uuid, 正在从 /etc/fstab 中移除相关条目"
            sed -i "\|UUID=${disk_uuid}|d" /etc/fstab  # 使用 \| 作为分隔符避免UUID中包含 / 导致sed错误
        fi
    done
done

# 清除磁盘上的所有数据和分区表
for disk in $disks; do
    echo "正在清除磁盘 /dev/${disk} 的所有数据"
    
    # 确保磁盘所有分区都已卸载
    partitions=$(lsblk -n -o NAME /dev/${disk} | grep -v "^${disk}$")
    for part in $partitions; do
        umount "/dev/${part}" 2>/dev/null
    done
    
    # 使用wipefs清除所有文件系统标识
    echo "正在清除文件系统标识..."
    wipefs -a "/dev/${disk}" && echo "文件系统标识已清除" || echo "清除文件系统标识失败"
    
    # 清除分区表开始部分
    echo "正在清除磁盘开头数据..."
    dd if=/dev/zero of="/dev/${disk}" bs=1M count=1 status=none && echo "磁盘开头数据已清除" || echo "清除磁盘开头数据失败"
    
    # 清除GPT分区表（如果存在）
    echo "正在清除GPT分区表..."
    sgdisk -Z "/dev/${disk}" 2>/dev/null && echo "GPT分区表已清除" || echo "清除GPT分区表失败或不存在GPT分区表"
    
    # 清除MBR分区表
    echo "正在清除MBR分区表..."
    echo -e "d\nw" | fdisk "/dev/${disk}" 2>/dev/null && echo "MBR分区表已清除" || echo "清除MBR分区表失败或不存在MBR分区表"
    
    echo "磁盘 /dev/${disk} 已完成清除"
    echo "----------------------------------------"
done

echo "所有磁盘清除完成"
echo "fstab备份文件已保存为 /etc/fstab.backup"
echo "请检查 /etc/fstab 确保配置正确"

