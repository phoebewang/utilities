#!/bin/bash
#Phoebe 2017.12.16


SIZE=2G
#SWAP=128M
#http://cdimage.ubuntu.com/ubuntu-base/releases/16.04/release/ubuntu-base-16.04-core-amd64.tar.gz
RTFS=ubuntu-base-16.04-core-amd64.tar.gz
#KERNEL=4.10.0-42
DRIVE=/dev/nbd0

[[ -z $SWAP ]] && SWAP=0
[[ "${SWAP:0-1:1}"x = "K"x ]] && SWAP=$((${SWAP:0:-1} * 1024))
[[ "${SWAP:0-1:1}"x = "M"x ]] && SWAP=$((${SWAP:0:-1} * 1024 * 1024))
[[ "${SWAP:0-1:1}"x = "G"x ]] && SWAP=$((${SWAP:0:-1} * 1024 * 1024 * 1024))


qemu-img create -f qcow2 ./core-ubuntu.img $SIZE
sudo modprobe nbd max_part=16
sudo qemu-nbd -c $DRIVE core-ubuntu.img
SIZE=`sudo fdisk -l $DRIVE | grep Disk | awk '{print $7}'`
ROOT=`echo $SIZE - $SWAP /512 | bc`
DELTA=33
SWAP_PT=
[[ $SWAP -gt 0 ]] && SWAP_PT=": type=82" && DELTA=0
sudo sfdisk $DRIVE -f << EOF
label: dos
unit: sectors
first-lba: 2048

: size=$(($ROOT - 2048 - $DELTA)), bootable
$SWAP_PT
EOF
sudo mkfs.ext4 $DRIVE"p1"
[[ $SWAP -gt 0 ]] && sudo mkswap $DRIVE"p2"


sudo mount $DRIVE"p1" /mnt
sudo tar -xpf $RTFS -C /mnt


UUID1=`sudo blkid /dev/nbd0p1 | awk '{print $2}' | cut -f 2 -d "\""`
UUID2=`sudo blkid /dev/nbd0p2 | awk '{print $2}' | cut -f 2 -d "\""`
UUID2_STR=
[[ ! -z $UUID2 ]] && UUID2_STR="UUID=$UUID2 none            swap    sw              0       0"
cat << EOF | sudo tee /mnt/etc/fstab
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=$UUID1 /               ext4    errors=remount-ro 0       1
$UUID2_STR
EOF


sudo cp -b /etc/resolv.conf  /mnt/etc/resolv.conf
cat << EOF | sudo tee /mnt/etc/apt/sources.list
deb http://mirrors.aliyun.com/ubuntu/ xenial main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ xenial-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ xenial-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ xenial-backports main restricted universe multiverse
##测试版源
deb http://mirrors.aliyun.com/ubuntu/ xenial-proposed main restricted universe multiverse
# 源码
deb-src http://mirrors.aliyun.com/ubuntu/ xenial main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-backports main restricted universe multiverse
##测试版源
deb http://mirrors.aliyun.com/ubuntu/ xenial-proposed main restricted universe multiverse
# 源码
deb-src http://mirrors.aliyun.com/ubuntu/ xenial main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-backports main restricted universe multiverse
##测试版源
deb-src http://mirrors.aliyun.com/ubuntu/ xenial-proposed main restricted universe multiverse
# Canonical 合作伙伴和附加
deb http://archive.canonical.com/ubuntu/ xenial partner
deb http://extras.ubuntu.com/ubuntu/ xenial main
EOF


INSTALL_CMD=
if [ ! -z $KERNEL ]; then
INSTALL_CMD=`cat << EOF
apt update
apt install -y net-tools ethtool ifupdown
apt install -y linux-headers-$KERNEL-generic
apt install -y linux-image-$KERNEL-generic
EOF
`
fi
cat << EOF | sudo tee /mnt/root/init.sh
echo root:root | chpasswd
$INSTALL_CMD
rm /root/init.sh
EOF
sudo chmod +x /mnt/root/init.sh


sudo mount -t proc /proc /mnt/proc
sudo mount -t sysfs /sys /mnt/sys
sudo mount -o bind /dev /mnt/dev
sudo chroot /mnt /root/init.sh
sudo umount /mnt/proc
sudo umount /mnt/sys
sudo umount /mnt/dev

if [ ! -z $KERNEL ]; then
sudo sed -i 's/GRUB_TIMEOUT=10/GRUB_TIMEOUT=0/' /mnt/etc/default/grub
sudo sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="console=ttyS0,115200 earlyprintk=serial"/' /mnt/etc/default/grub
fi
sudo umount $DRIVE"p1"
sudo qemu-nbd -d $DRIVE
