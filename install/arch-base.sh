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
unsafe=false

memory_real_size_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
drive_real_size_mb=$(lsblk -nbd -o SIZE /dev/sda | awk '{printf "%.0f\n", $1/1024/1024}')

drive_format_efi=ef00
drive_format_linux_swap=8200
drive_format_linux_filesystem=8300

keyboard_layout=us
network_available=false
boot_mode=""
drive=""
partition_format_boot=$drive_format_efi
partition_format_swap=$drive_format_linux_swap
partition_format_system=$drive_format_linux_filesystem
partition_size_boot=512M
partition_size_swap=""

###############
#  ARGUMENTS  #
###############

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

###############
#  FUNCTIONS  #
###############

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
		y|Y|yes|YES) echo "true" ;;
		*) echo "false" ;;
	esac
}

run_if_live() {
	if [ "$mode" != "live" ]; then
		echo -e "\nABORT - Last fallback before accidental command execution"
		echo "Please urgently review safety features in script"
		exit 1
	fi
	"$@"
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

# Swap partition size
max_swap=$(($drive_real_size_mb * 10 / 100))

# What's the goal?
# No more than 2x memory
# No more than 10% drive space

if (( memory_real_size_mb * 2 < max_swap)); then
	partition_size_swap="$((memory_real_size_mb * 2))M"
else
	partition_size_swap="${max_swap}M"
fi

echo
echo "Real Memory Size:	${memory_real_size_mb}M"
echo "Real Drive Size:	${drive_real_size_mb}M"
echo
echo "Partition Swap Size:	$partition_size_swap"
echo "Partition Boot Size:	$partition_size_boot"

# Boot Mode
echo
if [ -d /sys/firmware/efi ]; then
	read -r fw_size < /sys/firmware/efi/fw_platform_size
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

	drive="/dev/${safe_drives[${drive_num}]}"
	if [[ $(confirm "Proceed with ${drive_num}: ${drive}?") == "false" ]]; then
		drive=""
		continue
	fi
done


if [ "$mode" = "dry" ]; then
	exit 0
fi

##########
#  LIVE  #
##########

if [[ $(confirm "Proceed with live installation?") == "false" ]]; then
	abort "User aborted"
fi

run_if_live loadkeys "$keyboard_layout"
run_if_live timedatectl set-ntp true

# Partition
run_if_live sgdisk --zap-all "${drive}"
run_if_live sgdisk \
	-n 1:0:+"$partition_size_boot}"		-t 1:"${partition_format_boot}" \
	-n 2:0:+"${partition_size_swap}"	-t 2:"${partition_format_swap}" \
	-n 3:0:0							-t 3:"${partition_format_system}" \
	"${drive}"

partprobe "$drive"
lsblk "$drive"
