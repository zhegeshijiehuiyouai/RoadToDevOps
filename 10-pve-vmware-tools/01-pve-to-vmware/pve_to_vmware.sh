#!/bin/bash
# 需要先安装 expect，鉴于pve环境可能处于内网，故脚本不进行expect的安装，请手动安装。
# 脚本用法：传递pve虚拟机的id给脚本，脚本找出对应磁盘后，转格式，并通过scp传到一台esxi对应的
# 存储目录上。
# 之后在控制台上的操作都手动执行。

# 在该目录下查找硬盘
scan_dir=/dev
esxi_ip=172.16.201.3
esxi_ssh_port=22
esxi_ssh_user=root
esxi_ssh_password=yourpassword
# esxi上，存储的目录
esxi_store_dir=/vmfs/volumes/cd-md3820i-1
# 迁移到vm的哪台新建虚拟机上，这台虚拟机需要提前创建
esxi_vm_name=$2
# 第一个参数是pve虚拟机的id
pve_vm_id=$1

# 带格式的echo函数
function echo_info() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[32mINFO\033[0m] \033[37m$@\033[0m"
}
function echo_warning() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[1;33mWARNING\033[0m] \033[1;37m$@\033[0m"
}
function echo_error() {
    echo -e "[\033[36m$(date +%T)\033[0m] [\033[41mERROR\033[0m] \033[1;31m$@\033[0m"
}

function print_logo(){
echo " 
 _____ _____ _____    _          _____ _____                   
|  _  |  |  |   __|  | |_ ___   |  |  |     |_ _ _ ___ ___ ___ 
|   __|  |  |   __|  |  _| . |  |  |  | | | | | | | .'|  _| -_|
|__|   \___/|_____|  |_| |___|   \___/|_|_|_|_____|__,|_| |___|

"                                                    
}


########################### 脚本起始 #############################
print_logo

function print_usage() {
    echo
    echo "用法：$0 <pve虚拟机id> <esxi虚拟机名字>"
    echo
}

workdir=$(pwd)

if [ $# -ne 2 ];then
    echo_error 参数传递错误
    print_usage
    exit 1
fi

echo_info 查找虚拟机硬盘
vmdisks=$(find ${scan_dir} -name vm-${pve_vm_id}-disk* | sort)
if [ $? -ne 0 ];then
    echo_error 未找到虚拟机${pve_vm_id}的硬盘，退出
    exit 1
fi

realvmdisks_index=0
for vmdisk in ${vmdisks};do
    vmdisk_lnlocation=$(ls -l ${vmdisk} | awk '{print $NF}')
    cd $(dirname ${vmdisk})
    realvmdisk=$(realpath ${vmdisk_lnlocation})
    realvmdisks[${realvmdisk_index}]=${realvmdisk}
    # 利用下标，将vm虚拟机的硬盘（软链接）和真是硬盘对应起来
    recordvmdisks[${realvmdisk_index}]=$(basename ${vmdisk})
    let realvmdisk_index++
    echo "$vmdisk  （${realvmdisk}）"
done


echo_info 是否将以上硬盘文件转为vmdk格式（y\|n）？

function input_and_confirm() {
    read user_input
    case $user_input in
    n|N)
        echo_info 用户退出
        exit 2
        ;;
    y|Y)
        true
        ;;
    *)
        echo_warning 输入不合法，请重新输入（y\|n）
        input_and_confirm
        ;;
    esac
}

input_and_confirm
# 到这里的话，说明用户输入的是确认，即需要转换

function send_vmdk_to_esxi() {
    send_file=$1
    expect <<EOF
        set timeout 3600
        spawn scp -P $esxi_ssh_port $send_file $esxi_ssh_user@$esxi_ip:${esxi_store_dir}/${esxi_vm_name}
        expect {
            "yes/no" { send "yes\n";exp_continue }
            "Password" { send "$esxi_ssh_password\n" }
        }
        expect "Password" { send "$esxi_ssh_password\n" }
EOF
    if [ $? -ne 0 ];then
        echo_error 文件拷贝失败，退出
        exit 1
    fi
}

function convert_to_thin_disk() {
    # 精简置备盘的下标，esxi磁盘命名为vm.vmdk，vm_1.vmdk，vm_2.vmdk...
    thin_index=$1
    # 厚置备盘
    convert_disk=$2
    # 精简置备盘
    after_convert_disk=$3
    if [ ${thin_index} -eq 0 ];then
        expect <<EOF
            set timeout 14400
            spawn ssh -p $esxi_ssh_port $esxi_ssh_user@$esxi_ip
            expect "Password" { send "$esxi_ssh_password\n" }
            expect "root@" { send "cd ${esxi_store_dir}/${esxi_vm_name} && vmkfstools -i ${convert_disk} ${after_convert_disk}.vmdk -d thin && rm -f ${convert_disk}\n" }
            expect "root@" { send "exit\n" }
            expect eof 
EOF
    else
        expect <<EOF
            set timeout 14400
            spawn ssh -p $esxi_ssh_port $esxi_ssh_user@$esxi_ip
            expect "Password" { send "$esxi_ssh_password\n" }
            expect "root@" { send "cd ${esxi_store_dir}/${esxi_vm_name} && vmkfstools -i ${convert_disk} ${after_convert_disk}_${thin_index}.vmdk -d thin && rm -f ${convert_disk}\n" }
            expect "root@" { send "exit\n" }
            expect eof 
EOF
    fi
}



index=0
for disk in ${realvmdisks[@]};do
    echo "------------------------------------------------"
    # 转换格式后的文件，因为多次用到，所以搞了个变量
    final_file=${recordvmdisks[${index}]}.vmdk
    cd $(dirname ${disk})
    echo_info "$disk 转格式中..."
    qemu-img convert -f raw -O vmdk ${disk} ${final_file}
    if [ $? -ne 0 ];then
        echo_error $(realpath ${final_file}) 转换格式失败
        exit 2
    fi
    echo_info 拷贝vmdk文件至esxi服务器
    send_vmdk_to_esxi ${final_file}
    echo_info 厚置备盘转换为精简置备盘
    convert_to_thin_disk ${index} ${final_file} ${esxi_vm_name}
    # 因为磁盘文件一般都很大，所以拷贝完后及时删除
    rm -f ${final_file}
    let index++
done

echo_info pve虚拟机（ID：${pve_vm_id}）硬盘已迁移至esxi：$esxi_ip:${esxi_store_dir}/${esxi_vm_name}，剩下操作请手动执行

