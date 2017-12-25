IMG=core-ubuntu.img
[[ ! -z $1 ]] && IMG=$1

sudo modprobe nbd max_part=16 &&
sudo qemu-nbd -c /dev/nbd0 $IMG
sudo mount /dev/nbd0p2 /mnt
sudo mount /dev/nbd0p1 /mnt/boot/efi
sudo mount -t proc /proc /mnt/proc
sudo mount -t sysfs /sys /mnt/sys
sudo mount -o bind /dev /mnt/dev
sudo chroot /mnt
sudo umount /mnt/proc &&
sudo umount /mnt/sys &&
sudo umount /mnt/dev &&
sudo umount /dev/nbd0p1 &&
sudo umount /dev/nbd0p2 &&
sudo qemu-nbd -d /dev/nbd0
