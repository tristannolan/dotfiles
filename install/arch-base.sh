#!/bin/sh

# Usage
# Create a bootable usb drive with an arch iso
# Boot arch

# Download the file
# curl -sL [URL] -o $SCRIPT.sh

# Edit to configure settings
# sudo $SCRIPT.sh

# Settings
safe_to_run=false

# Arguments
case "$1" in
	unsafe|true|1)
		unsafe=true
		;;
	*)
	unsafe=false
	;;
esac

# Script
#read -p "Prompting a question: " answer
#echo $answer

if [ "$safe_to_run" != "true" ] && [ "$unsafe" != "true" ]; then
	echo "Aborting - Not safe to run"
	echo "Please review and modify settings before continuing"
	exit 1
fi
