#!/bin/bash

set -e

# Ensure the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or using sudo."
    exit 1
fi

# Display available disks and prompt user selection
lsblk -d -o NAME,SIZE,TYPE,MODEL

read -p "Enter the name of the disk to format (e.g., sda): " DISK

if [ -z "$DISK" ] || [ ! -b "/dev/$DISK" ]; then
    echo "Invalid disk selected. Exiting."
    exit 1
fi

read -p "Are you sure you want to format /dev/$DISK? All data will be lost! (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Operation aborted."
    exit 1
fi

# Wipe the disk and create a new partition table
echo "Wiping disk and creating new partition table on /dev/$DISK..."
sgdisk --zap-all /dev/$DISK
wipefs --all /dev/$DISK

# Encrypt the disk
read -p "Do you want to encrypt the root partition? (yes/no): " ENCRYPT_DISK

# Create partitions
parted -s /dev/$DISK mklabel gpt

# EFI partition
parted -s /dev/$DISK mkpart primary fat32 1MiB 1GiB
parted -s /dev/$DISK set 1 esp on

# Prompt for swap partition
read -p "Do you want to create a swap partition? (yes/no): " CREATE_SWAP
if [ "$CREATE_SWAP" == "yes" ]; then
    read -p "Enter the size of the swap partition (e.g., 2G): " SWAP_SIZE
    if [[ ! $SWAP_SIZE =~ ^[0-9]+[MG]$ ]]; then
        echo "Invalid size format. Exiting."
        exit 1
    fi
    parted -s /dev/$DISK mkpart primary linux-swap 1GiB $SWAP_SIZE
    SWAP_END=$SWAP_SIZE
else
    SWAP_END=1GiB
fi

# Root partition
parted -s /dev/$DISK mkpart primary ext4 $SWAP_END 100%

if [ "$ENCRYPT_DISK" == "yes" ]; then
    echo "Encrypting the root partition..."
    cryptsetup luksFormat /dev/${DISK}3
    cryptsetup open /dev/${DISK}3 cryptroot
    ROOT_PART=/dev/mapper/cryptroot
else
    ROOT_PART=/dev/${DISK}3
fi

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 /dev/${DISK}1
if [ "$CREATE_SWAP" == "yes" ]; then
    mkswap /dev/${DISK}2
    swapon /dev/${DISK}2
fi
mkfs.btrfs -f $ROOT_PART

# Mount partitions for Arch Linux installation
echo "Mounting root partition with Btrfs subvolumes..."
mount $ROOT_PART /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@snapshots
umount /mnt

mount -o compress=zstd,subvol=@ $ROOT_PART /mnt
mkdir -p /mnt/{boot,home,var,tmp,.snapshots}
mount -o compress=zstd,subvol=@home $ROOT_PART /mnt/home
mount -o compress=zstd,subvol=@var $ROOT_PART /mnt/var
mount -o compress=zstd,subvol=@tmp $ROOT_PART /mnt/tmp
mount -o compress=zstd,subvol=@snapshots $ROOT_PART /mnt/.snapshots

mkdir -p /mnt/boot
mount /dev/${DISK}1 /mnt/boot

# Install essential packages
echo "Installing base packages..."
pacstrap /mnt base base-devel linux linux-firmware git linux-firmware-marvell btrfs-progs vim networkmanager grub efibootmgr grub-btrfs timeshift sudo openssh

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system and configure
arch-chroot /mnt /bin/bash <<EOF

# Set timezone
ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime
hwclock --systohc

# Set localization
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
read -p "Enter the hostname for this system: " HOSTNAME
echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.1.1\t$HOSTNAME.localdomain\t$HOSTNAME" >> /etc/hosts

# Set root password
echo "Set root password:"
passwd

# Enable NetworkManager
systemctl enable NetworkManager

#Install linux-surface
curl -s https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc \
    | sudo pacman-key --add -
sudo pacman-key --finger 56C464BAAC421453
sudo pacman-key --lsign-key 56C464BAAC421453
echo -e "\n[linux-surface]\nServer = https://pkg.surfacelinux.com/arch/" >> /etc/pacman.conf
sudo pacman -Syu
sudo pacman -S linux-surface linux-surface-headers iptsd

# Install bootloader
mkdir -p /boot/efi
mount /dev/${DISK}1 /boot/efi
if [ "$ENCRYPT_DISK" == "yes" ]; then
    sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cryptdevice=UUID=$(blkid -s UUID -o value /dev/${DISK}3):cryptroot root=$ROOT_PART"/' /etc/default/grub
fi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Unmount partitions and finish
umount -R /mnt
if [ "$CREATE_SWAP" == "yes" ]; then
    swapoff /dev/${DISK}2
fi

echo "Installation complete. You can now reboot into your new Arch Linux system."
