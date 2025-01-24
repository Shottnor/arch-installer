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

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 /dev/${DISK}1
if [ "$CREATE_SWAP" == "yes" ]; then
    mkswap /dev/${DISK}2
    swapon /dev/${DISK}2
fi
mkfs.ext4 /dev/${DISK}3

# Display results
echo "Disk /dev/$DISK has been formatted and partitioned as follows:"
lsblk /dev/$DISK

# Mount partitions for Arch Linux installation
read -p "Would you like to mount the partitions now for Arch Linux installation? (yes/no): " MOUNT_CONFIRM
if [ "$MOUNT_CONFIRM" == "yes" ]; then
    mkdir -p /mnt
    if [ "$CREATE_SWAP" == "yes" ]; then
        mount /dev/${DISK}3 /mnt
    else
        mount /dev/${DISK}2 /mnt
    fi
    mkdir -p /mnt/boot
    mount /dev/${DISK}1 /mnt/boot

    echo "Partitions mounted at /mnt and /mnt/boot. Proceed with Arch Linux installation."
else
    echo "You can mount the partitions later using the following commands:"
    echo "  mount /dev/${DISK}3 /mnt"
    echo "  mkdir -p /mnt/boot && mount /dev/${DISK}1 /mnt/boot"
    if [ "$CREATE_SWAP" == "yes" ]; then
        echo "  swapon /dev/${DISK}2"
    fi
fi

echo "Done."
