#!/bin/bash
set -euo pipefail

# Splash screen
# Gather information
# Present config
# Confirm key actions like drive choice and partition
# Dry: echo commands
# Live: run commands

###################
#    CONSTANTS    #
###################
FORMAT_EFI=ef00
FORMAT_BIOS_BOOT=ef02
FORMAT_LINUX_SWAP=8200
FORMAT_LINUX_FILESYSTEM=8300

BOOT_MODE_UEFI=uefi
BOOT_MODE_BIOS=bios

DEFAULT_TIMEZONE=Africa/Johannesburg

##################
#    SETTINGS    #
##################
mode=safe
unsafe=false

keyboard_layout=us
network_available=false
boot_mode=""
drive=""
hostname=""
username=""
root_password=""
user_password=""
country="South Africa"

partition_size_swap=""

packages_common=(
	linux
	linux-lts
	linux-firmware
	base
	vim
	networkmanager
	dhcpcd
	netctl
	wpa_supplicant
	dialog
)
packages_uefi=(
	systemd-boot
	efibootmgr
)
packages_bios=(
	grub
)

###################
#    ARGUMENTS    #
###################

usage() {
	echo "Usage: $0 [options...]"
	echo "-u, --unsafe"
	echo "-m, --mode	safe|dry|live"
}

while getopts ":hum:" opt; do
	case "${opt}" in
		h)
			usage
			exit 0
			;;
		u)
			unsafe="true"
			echo "UNSAFE EXECUTION - ABORT WILL BE IGNORED"
			;;
		m)
			case "${OPTARG}" in
				safe|dry|live) 
					mode="${OPTARG}" 
					;;
				*) 
					echo "Invalid Mode: $OPTARG"
					usage
					exit 1
					;;
			esac
			;;
		*)
			echo "Invalid Argument: ${OPTARG}"
			usage
			exit 1
		;;
	esac
done
shift $((OPTIND - 1))

###################
#    FUNCTIONS    #
###################

abort() {
	local reason=${1:-}
	local info=${2:-}
	local title="\nABORTING"

	if [ -z "$reason" ]; then
		echo "$title"
		exit 1
	fi

	echo -e "$title - $reason" >&2
	if [ -n "$info" ]; then
		echo -e "$info" >&2
	fi

	if [ $unsafe = "true" ]; then
		echo -e "\nUNSAFE - IGNORING ABORT"
		return
	fi
	exit 1
}

confirm() {
	local question=${1:-}

	if [ -z "$question" ]; then
		abort "confirm()" "No question string provided"
	fi

	read -r -p "$question [y/N]: " answer
	case "$answer" in
		y|Y|yes|YES)	return 0 ;;
		*)				return 1 ;;
	esac
}

#############
#    DRY    #
#############

if [ "$mode" = "safe" ]; then
	abort "Will not run in safe mode" "Please review and modify settings before continuing"
fi

# Keyboard layout
echo "Keyboard Layout: $keyboard_layout"

# Internet
if ping -c 1 8.8.8.8 &> /dev/null; then
	echo "Network Available"
	network_available=true
else
	abort "Network unavailable" "Please review device and installer config"
fi

# Boot Mode
echo
if [ -d /sys/firmware/efi ]; then
	read -r fw_size < /sys/firmware/efi/fw_platform_size
	case "$fw_size" in
		64)
			echo "Boot Mode: 64-bit x64 UEFI"
			boot_mode=$BOOT_MODE_UEFI
			;;
		32)
			abort "Automatic install not configured for 32-bit UEFI"
			;;
		*)
			abort "Unknown platform size" "Unable to determine if UEFI is 64 or 32 bit"
			;;
	esac
else
	echo "Boot Mode: BIOS"
	boot_mode=$BOOT_MODE_BIOS
fi

# Select a drive to partition
mapfile -t drives < <(lsblk -dn -o NAME,TYPE | awk '$2=="disk" { print $1 }')

safe_drives=()
for d in "${drives[@]}"; do
	if ! lsblk -nr -o MOUNTPOINTS "/dev/$d" | grep -q '[^[:space:]]'; then
		safe_drives+=("$d")
	fi
done

if [[ "${#safe_drives[@]}" -eq 0 ]]; then
	lsblk_output=$(lsblk)
	abort "No drive available" "Please confirm if an unmounted drive is available for partitioning. \n\n${lsblk_output}"
else
	while [ -z "$drive" ]; do
		echo -e "\nAvailable drives:"
		for i in "${!safe_drives[@]}"; do
			echo "$i: /dev/${safe_drives[$i]}"
		done

		read -p "Please select a drive to partition: " drive_num

		if [[ ! "$drive_num" =~ ^[0-9]+$ ]]; then
			echo "Invalid input"
			continue
		fi

		if [[ "$drive_num" -lt 0 || "$drive_num" -ge "${#safe_drives[@]}" ]]; then
			echo "Selection out of bounds"
			continue
		fi

		drive="/dev/${safe_drives[${drive_num}]}"

		if ! confirm "Proceed with ${drive}?"; then
			drive=""
			continue
		fi
	done
fi

# Swap partition size
memory_real_size_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
drive_real_size_mb=$(lsblk -nbd -o SIZE "${drive}" | awk '{printf "%.0f\n", $1/1024/1024}')

max_swap=$(($drive_real_size_mb * 10 / 100))

# The arch wiki recommends at least 4GB for swap
if (( max_swap < 4 * 1024 )); then
	partition_size_swap=4G
elif (( memory_real_size_mb * 2 < max_swap)); then
	partition_size_swap="$((memory_real_size_mb * 2))M"
else
	partition_size_swap="${max_swap}M"
fi

echo
echo "Real Memory Size:	${memory_real_size_mb}M"
echo "Real Drive Size:	${drive_real_size_mb}M"
echo
echo "Partition Swap Size:	$partition_size_swap"

# Gather Hostname
while [ -z "$hostname" ]; do
	read -p "Enter a hostname: " hostname

	if (( "${#hostname}" == 0 )); then
		echo "Hostname cannot be nil"
		continue
	fi

	if ! confirm "Proceed with '${hostname}'?"; then
		continue
	fi

	break
done

# Gather Root Password
while [ -z "$root_password" ]; do
	read -p "Enter a root password: " root_password

	if (( "${#root_password}" == 0 )); then
		echo "Password cannot be nil"
		continue
	fi

	if ! confirm "Proceed with '${root_password}'?"; then
		continue
	fi

	break
done

# Gather Username
while [ -z "$username" ]; do
	read -p "Enter a username: " username

	if (( "${#username}" == 0 )); then
		echo "Username cannot be nil"
		continue
	fi

	if ! confirm "Proceed with '${username}'?"; then
		continue
	fi

	break
done

# Gather User Password
while [ -z "$user_password" ]; do
	read -p "Enter a user password: " user_password

	if (( "${#user_password}" == 0 )); then
		echo "Password cannot be nil"
		continue
	fi

	if ! confirm "Proceed with '${user_password}'?"; then
		continue
	fi

	break
done

timezone=$(curl https://ipapi.co/timezone) || $DEFAULT_TIMEZONE

if [ "$mode" = "dry" ]; then
	exit 0
fi

##############
#    LIVE    #
##############

if [ "$mode" != "live" ]; then
	abort "Not in live mode" "Please urgently review safety features in script"
fi

echo -e "\nProceed with live installation?"
if ! confirm "WARNING - This could break your computer"; then
	exit 0
fi

loadkeys "$keyboard_layout"
timedatectl set-ntp true

# Partition and format
case "$boot_mode" in 
	"${BOOT_MODE_UEFI}")
		sgdisk --zap-all "$drive"
		sgdisk \
			-n 1:0:+512M					-t 1:"$FORMAT_EFI"				\
			-n 2:0:+"$partition_size_swap"	-t 2:"$FORMAT_LINUX_SWAP"		\
			-n 3:0:0						-t 3:"$FORMAT_LINUX_FILESYSTEM"	\
			"$drive"

		partprobe "$drive"

		mkfs.vfat -F32 "${drive}1"
		mkswap "${drive}2"
		mkfs.ext4 "${drive}3"

		swapon "${drive}2"
		mount "${drive}3" /mnt
		mkdir -p /mnt/boot/efi
		mount "${drive}1" /mnt/boot/efi
		;;

	"${BOOT_MODE_BIOS}")
		sgdisk --zap-all "$drive"
		sgdisk \
			-n 1:0:+2M						-t 1:"$FORMAT_BIOS_BOOT"		\
			-n 2:0:+"$partition_size_swap"	-t 2:"$FORMAT_LINUX_SWAP"		\
			-n 3:0:0						-t 3:"$FORMAT_LINUX_FILESYSTEM"	\
			"$drive"

		partprobe "$drive"

		mkswap "${drive}2"
		mkfs.ext4 "${drive}3"

		swapon "${drive}2"
		mount "${drive}3" /mnt
		;;
esac

# Select a nearby mirror server
reflector						\
	-l 20						\
	--country "'${country}'"	\
	--age 12					\
	--protocol https			\
	--sort rate					\
	--save /etc/pacman.d/mirrorlist

# Essential packages
case "$boot_mode" in
	"${BOOT_MODE_UEFI}")
		pacstrap /mnt "${packages_common[@]}" "${packages_uefi[@]}"
		;;
	"${BOOT_MODE_BIOS}")
		pacstrap /mnt "${packages_common[@]}" "${packages_bios[@]}"
		;;
esac

genfstab /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
set -e

echo "setting hostname"
echo "$hostname" > /etc/hostname

# users
echo "setting root password ${root_password}"
echo "root:$(root_password)" | chpasswd

echo "setting user: ${username} ${user_password}"
echo "${username}:${user_password}" | chpasswd

# working until here

# Time and location
ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime
hwclock --systohc
# set locale?
#locale-gen

echo KEYMAP=es > /etc/wconsole.conf
echo LANG=es_AR.UTF8 > /etc/local.conf

mkinitcpio -P

# Install Bootloader
case "$boot_mode" in
	"${BOOT_MODE_UEFI}")
		;;
	"${BOOT_MODE_BIOS}")
		grub-install "${drive}"
		grub-mkconfig -o /boot/grub/grub.cfg
		;;

esac

# Authentication
# Unmount and reboot
exit umount -R /mnt
#reboot

echo "unmounted, ready to reboot"

EOF
