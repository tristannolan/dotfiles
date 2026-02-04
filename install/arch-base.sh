#!/bin/bash

# Usage
# Create a bootable usb drive with an arch iso
# Boot the vm/pc

# curl https://raw.githubusercontent.com/tristannolan/dotfiles/refs/heads/main/install/arch-base.sh -o arch-base.sh
# vim arch-base.sh
# chmod +x arch-base.sh
# ./arch-base.sh safe

##############
#  Settings  #
##############
safe_to_run=false
live=false

mode_live=false			# commands won't run unless live
mode_safe=false			# protection against accidental curl run on bare metal

mode=safe	# safe|dry|unsafe|live

keyboard_layout=us

###############
#  Arguments  #
###############
case "$1" in
	live)
		live_mode=true
		;;
	dry)
		live_mode=false
		;;
	*)
	live_mode=$live
	;;
esac

case "$2" in
	unsafe)
		safe_mode=false
		;;
	safe)
		safe_mode=true
		;;
	*)
	safe_mode=$safe_to_run
	;;
esac

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
	if [ "$live_mode" != "true" ]; then
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

# Safety net
if [ "$safe_to_run" != "true" ] && [ "$safe_mode" != "true" ]; then
	abort "Not safe to run" "Please review and modify settings before continuing"
fi

# Keyboard layout
echo "Keyboard Layout: $keyboard_layout"
run_if_live "loadkeys es"

# Boot Mode
case $(cat /sys/firmware/efi/fw_platform_size) in
	64)
		echo "Boot Mode: 64-bit x64 UEFI"
		;;
	32)
		abort "Automatic install not configured for 32 bit system"
		;;
	*)
	# EUFI not found, likely in BIOS mode
	;;
esac
