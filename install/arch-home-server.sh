# TODO: Turn this into an installable home server install script
# Complete with interface, error detection, and my config

#!/bin/bash
set -euo pipefail

# init
loadkeys us
timedatectl set-ntp true

# partitions
sgdisk --zap-all /dev/sda
sgdisk \
	-n 1:0:+512M	 -t 1:ef00	\
	-n 2:0:+8192M	 -t 2:8200	\
	-n 3:0:0		 -t 3:8300	\
	/dev/sda

partprobe /dev/sda

mkfs.vfat -F32 -n EFI /dev/sda1
mkswap -L SWAP /dev/sda2
mkfs.ext4 -L ROOT /dev/sda3

swapon /dev/sda2
mount /dev/sda3 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot

# mirrorlist
reflector						\
	-l 20						\
	--country "South Africa"		\
	--age 12					\
	--protocol https			\
	--save /etc/pacman.d/mirrorlist

# vconsole
mkdir /mnt/etc
cat > /mnt/etc/vconsole.conf << EOF
FONT=default8x16
KEYMAP=us
XKBLAYOUT=us
XKBMODEL=pc105+inet
XKBOPTIONS=terminate:ctrl_alt_bksp
EOF

# Essential packages
pacstrap /mnt		\
	linux			\
	linux-lts		\
	linux-firmware	\
	base			\
	vim				\
	networkmanager	\
	dialog			\
	efibootmgr		\
	openssh			\
	intel-ucode		\
	sudo			\
	man				\
	git				\

genfstab /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash

exit # CAN'T PROCEED WITH SCRIPT, RUN THESE MANUALLY

echo "aurora" > /etc/hostname
passwd
useradd -m USER
passwd USER

# ADD USER TO SUDO
sudo useradd -aG wheel USER
sudo EDITOR=vim visudo
# Uncomment:
# %wheel ALL=(ALL) ALL

ln -sf /usr/share/zoneinfo/Africa/Johannesburg /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

mkinitcpio -P

bootctl install
mkdir -p /boot/loader
echo "default arch" > /boot/loader/loader.conf
echo "timeout 3" >> /boot/loader/loader.conf

mkdir -p /boot/loader/entries
# UPDATE PART UUID IN EXECUTION
blkid /dev/sda3
cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd	/intel-ucode.img
initrd  /initramfs-linux.img
options root=PARTUUID=<PARTUUID> rw
EOF

systemctl enable sshd
systemctl enable NetworkManager
systemctl enable systemd-timesyncd

exit 
umount -R /mnt
shutdown
# REMOVE USB DRIVE
# BOOT PC
