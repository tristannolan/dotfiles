#!/bin/bash
set -euo pipefail

# Usage
# Create a bootable usb drive with an arch iso
# Boot the vm/pc
# curl to download raw file
# Configure and run

##############
#  SETTINGS  #
##############
mode=safe

keyboard_layout=us
network_available=false
boot_mode=""
drive=""

###############
#  ARGUMENTS  #
###############

usage() {
	echo "Usage: $0 [options...]"
	echo "-m	safe|dry|live"
}

while getopts ":hm:" opt; do
	case "${opt}" in
		h)
			usage
			exit 0
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

###############
#  FUNCTIONS  #
###############

abort() {
	local reason=${1:-}
	local info=${2:-}

	if [ -z "$reason" ]; then
		echo "Aborting"
		exit 1
	fi

	echo -e "Aborting - $reason"
	if [ -n "$info" ]; then
		echo -e "$info"
	fi
	exit 1
}

#########
#  DRY  #
#########

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
if [ -d /sys/firmware/efi ]; then
	fw_size=$(cat /sys/firmware/efi/fw_platform_size)
	case "$fw_size" in
		64)
			echo "Boot Mode: 64-bit x64 UEFI"
			boot_mode="uefi"
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
	boot_mode="bios"
fi

# Select a drive to partition
mapfile -t drives < <(lsblk -dn -o NAME,TYPE,MOUNTPOINTS | awk '$2=="disk" && $1!="zram0" { print $1 }')

safe_drives=()
for d in "${drives[@]}"; do
	if ! lsblk -nr -o MOUNTPOINTS "/dev/$d" | grep -q .; then
		safe_drives+=("$d")
	fi
done

if [[ "${#safe_drives[@]}" -eq 0 ]]; then
	lsblk_output=$(lsblk)
	abort "Select Drive" "No mountable drives available. Please confirm that an unused drive is available for partitioning. \n${lsblk_output}"
fi

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

	drive="${safe_drives[${drive_num}]}"
	echo "You have selected drive ${drive_num}: ${drive}"
done

exit 1

##########
#  LIVE  #
##########

if [ "$mode" = "dry" ]; then
	echo -e "\nExiting Dry Run - No commands have been run"
	exit 0
fi

read -r -p "Proceed with live installation? [y/N]: " confirm
case "$confirm" in
	y|Y|yes|YES) ;;
	*) abort "User aborted"
esac

loadkeys $keyboard_layout
timedatectl set-ntp true
lsblk

# create partitions here
#
# Find the correct drive
# lsblk	
#
# Begin partitioning
# parted /dev/vda
