#!/bin/bash

# Usage
# Create a bootable usb drive with an arch iso
# Boot the vm/pc

# curl https://raw.githubusercontent.com/tristannolan/dotfiles/refs/heads/main/install/arch-base.sh -o arch-base.sh
# vim arch-base.sh
# chmod +x arch-base.sh
# ./arch-base.sh

##############
#  Settings  #
##############
mode=safe

keyboard_layout=us
boot_mode=""

###############
#  Arguments  #
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
				safe|dry|live) mode="${OPTARG}" ;;
				*) mode="safe" ;;
			esac
			;;
		*)
			if [ -n "${OPTARG}" ]; then
				echo "Invalid argument: ${OPTARG}"
			fi
			usage
			exit 1
		;;
	esac
done
shift $((OPTIND - 1))

###############
#  Functions  #
###############

abort() {
	reason=$1
	info=$2

	if [ -z "$reason" ]; then
		echo "Aborting"
		exit 1
	fi

	echo "Aborting - $reason"
	if [ -n "$info" ]; then
		echo "$info"
	fi
	exit 1
}

run_if_live() {
	if [ "$mode" != "live" ]; then
		return
	fi

	cmd=$1

	if [ -z "$cmd" ]; then
		abort "Attempted to execute empty command"
	fi

	$cmd
}

#############
#  Execute  #
#############

if [ "$mode" == "safe" ]; then
	abort "Will not run in safe mode" "Please review and modify settings before continuing"
fi

# Keyboard layout
echo "Keyboard Layout: $keyboard_layout"
run_if_live "loadkeys $keyboard_layout"

# Boot Mode
if [ -d /sys/firmware/efi ]; then
	case $(cat /sys/firmware/efi/fw_platform_size) in
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
