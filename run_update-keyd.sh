#!/bin/sh
set -e

sudo mkdir -p /etc/keyd
sudo cp ~/.local/share/chezmoi/dot_config/keyd/tristannolan.conf /etc/keyd/default.conf
sudo chown root:root /etc/keyd/default.conf
sudo chmod 644 /etc/keyd/default.conf
sudo keyd reload
