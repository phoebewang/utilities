#!/bin/bash
#Phoebe 2017.12.16


UEFI=100M
SIZE=2G
#SWAP=128M
#http://cdimage.ubuntu.com/ubuntu-base/releases/16.04/release/ubuntu-base-16.04-core-amd64.tar.gz
RTFS=ubuntu-base-16.04-core-amd64.tar.gz
KERNEL=4.10.0-42
DRIVE=/dev/nbd0

function size_in_byte()
{
    BYTES=$1
    [[ -z $BYTES ]] && BYTES=0
    [[ "${BYTES:0-1:1}"x = "K"x ]] && BYTES=$((${BYTES:0:-1} * 1024))
    [[ "${BYTES:0-1:1}"x = "M"x ]] && BYTES=$((${BYTES:0:-1} * 1024 * 1024))
    [[ "${BYTES:0-1:1}"x = "G"x ]] && BYTES=$((${BYTES:0:-1} * 1024 * 1024 * 1024))
    echo $BYTES
}


UEFI=`size_in_byte $UEFI`
SWAP=`size_in_byte $SWAP`

qemu-img create -f qcow2 ./core-ubuntu.img $SIZE
sudo modprobe nbd max_part=16
sudo qemu-nbd -c $DRIVE core-ubuntu.img
SIZE=`sudo fdisk -l $DRIVE | grep Disk | awk '{print $7}'`
ROOT=`echo $SIZE - $(($SWAP + $UEFI)) /512 | bc`
DELTA=33
SWAP_PT=
UEFI_PT=
BOOT_PT=", bootable"
DISK_LABEL=dos
[[ $SWAP -gt 0 ]] && SWAP_PT=": type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F" && DELTA=0
[[ ! -z $UEFI ]] && UEFI_PT=": size=$(($UEFI / 512)), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, bootable" && BOOT_PT=
DISK_LABEL=gpt
sudo sfdisk $DRIVE -f << EOF
label: $DISK_LABEL
unit: sectors
first-lba: 2048

$UEFI_PT
: size=$(($ROOT - 2048 - $DELTA))$BOOT_PT
$SWAP_PT
EOF
if [[ ! -z $UEFI ]]; then
sudo mkfs.vfat -F32 $DRIVE"p1"
sudo mkfs.ext4 $DRIVE"p2"
[[ $SWAP -gt 0 ]] && sudo mkswap $DRIVE"p3"
sudo mount $DRIVE"p2" /mnt
sudo mkdir -p /mnt/boot/efi
sudo mount $DRIVE"p1" /mnt/boot/efi
sudo mkdir -p /mnt/boot/efi/EFI/BOOT
sudo grub-mkimage -o /mnt/boot/efi/EFI/BOOT/bootx64.efi -O x86_64-efi -p /EFI/BOOT search search_fs_file configfile help iso9660 fat part_gpt part_msdos disk exfat ext2 ntfs appleldr hfs normal reiserfs font linux chain
#sudo grub-install $DRIVE
else
sudo mkfs.ext4 $DRIVE"p1"
[[ $SWAP -gt 0 ]] && sudo mkswap $DRIVE"p2"
sudo mount $DRIVE"p1" /mnt
fi
sudo tar -xpf $RTFS -C /mnt


UUID1=`sudo blkid /dev/nbd0p1 | awk '{print $2}' | cut -f 2 -d "\""`
UUID2=`sudo blkid /dev/nbd0p2 | awk '{print $2}' | cut -f 2 -d "\""`
UUID3=`sudo blkid /dev/nbd0p3 | awk '{print $2}' | cut -f 2 -d "\""`
[[ -z $UEFI ]] && UUID3=$UUID2 && UUID2=$UUID1 && UUID1=
UUID1_STR=
[[ ! -z $UUID1 ]] && UUID1_STR="UUID=$UUID1 /boot/efi       vfat    umask=0077      0       1" &&
cat << EOF | sudo tee /mnt/boot/efi/EFI/BOOT/grub.cfg
search.fs_uuid $UUID2 root hd0,gpt2
set prefix=(\$root)'/boot/grub'
configfile \$prefix/grub.cfg
EOF
UUID3_STR=
[[ ! -z $UUID3 ]] && UUID3_STR="UUID=$UUID3 none            swap    sw              0       0"
cat << EOF | sudo tee /mnt/etc/fstab
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=$UUID2 /               ext4    errors=remount-ro 0       1
$UUID1_STR
$UUID3_STR
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
#apt install -y linux-headers-$KERNEL-generic
apt install -y linux-image-$KERNEL-generic
apt install -y grub-efi-amd64
grub-install --target=x86_64-efi $DRIVE
sed -i 's/GRUB_TIMEOUT=10/GRUB_TIMEOUT=1/' /etc/default/grub
sed -i 's/GRUB_HIDDEN_TIMEOUT=0/#GRUB_HIDDEN_TIMEOUT=0/' /etc/default/grub
sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="console=ttyS0,115200"/' /etc/default/grub
update-grub
sed -i 's/nbd0p/sda/' /boot/grub/grub.cfg
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

if [[ ! -z $UEFI ]]; then
sudo umount $DRIVE"p1"
sudo umount $DRIVE"p2"
else
sudo umount $DRIVE"p1"
fi
sudo qemu-nbd -d $DRIVE
