#!/bin/bash

KERNEL_VERSION="5.4.130-1"

wget https://elrepo.org/linux/kernel/el7/x86_64/RPMS/kernel-lt-${KERNEL_VERSION}.el7.elrepo.x86_64.rpm
rpm -ivh kernel-lt-${KERNEL_VERSION}.el7.elrepo.x86_64.rpm
cat /boot/grub2/grub.cfg | grep menuentry
grub2-set-default "CentOS Linux (${KERNEL_VERSION}.el7.elrepo.x86_64) 7 (Core)"
grub2-editenv list
grub2-mkconfig -o /boot/grub2/grub.cfg
reboot