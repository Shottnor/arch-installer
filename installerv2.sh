#!/bin/bash
sudo pacman -S --needed git base-devel && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si
curl -s https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc \
    | sudo pacman-key --add -
sudo pacman-key --finger 56C464BAAC421453
sudo pacman-key --lsign-key 56C464BAAC421453
echo -e "\n[linux-surface]\nServer = https://pkg.surfacelinux.com/arch/" >> /etc/pacman.conf
sudo pacman -Syu
sudo pacman -S linux-surface linux-surface-headers iptsd linux-firmware-marvell
grub-mkconfig -o /boot/grub/grub.cfg
