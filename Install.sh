#!/bin/bash
set -e

DISK=/dev/nvme0n1

echo ">>> Partitioning Disk"
sgdisk -Z $DISK
sgdisk -n 1:0:+500M -t 1:ef00 $DISK
sgdisk -n 2:0:+150G -t 2:8300 $DISK
sgdisk -n 3:0:0     -t 3:8300 $DISK

echo ">>> Formatting Partitions"
mkfs.vfat -F32 ${DISK}p1
mkfs.ext4 ${DISK}p2
mkfs.ext4 ${DISK}p3

echo ">>> Mounting"
mount ${DISK}p2 /mnt
mkdir /mnt/efi
mkdir /mnt/home
mount ${DISK}p1 /mnt/efi
mount ${DISK}p3 /mnt/home

echo ">>> Installing Base System"
pacstrap /mnt base linux linux-firmware networkmanager nano sudo curl git pipewire pipewire-pulse pipewire-alsa pipewire-jack

echo ">>> Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo ">>> Chrooting and configuring"
arch-chroot /mnt /bin/bash << EOF

ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "arch" > /etc/hostname

echo ">>> Enabling NetworkManager"
systemctl enable NetworkManager

echo ">>> Creating user"
useradd -m -G wheel arch
echo "Set password for root:"
passwd
echo "Set password for user arch:"
passwd arch

sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo ">>> Installing GNOME + drivers"
pacman --noconfirm -S gnome gnome-tweaks gnome-shell-extensions \
bluez bluez-utils \
intel-ucode amd-ucode nvidia nvidia-utils nvidia-settings \
xorg-xwayland

systemctl enable gdm

echo ">>> Installing systemd-boot"
bootctl install

cat << BOOT > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=UUID=$(blkid -s UUID -o value ${DISK}p2) rw
BOOT

echo ">>> Installing macOS WhiteSur Theme"
pacman --noconfirm -S sassc jq imagemagick unzip

sudo -u arch bash << THEME
cd ~
git clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git
git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git
git clone https://github.com/vinceliuice/WhiteSur-cursors.git

# Install GTK with BLUE accent
cd WhiteSur-gtk-theme
./install.sh --theme blue --icon blue --normal --round

cd ../WhiteSur-icon-theme
./install.sh

cd ../WhiteSur-cursors
sudo ./install.sh
THEME

echo ">>> Enabling macOS-style GNOME Layout"
sudo -u arch bash << LAYOUT
gsettings set org.gnome.desktop.interface gtk-theme "WhiteSur-light-blue"
gsettings set org.gnome.desktop.interface icon-theme "WhiteSur"
gsettings set org.gnome.desktop.interface cursor-theme "WhiteSur-cursors"
gsettings set org.gnome.desktop.interface accent-color 'blue'

# macOS dock style
gnome-extensions enable dash-to-dock@micxgx.gmail.com
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false
gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'DYNAMIC'
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.5

# macOS top bar
gsettings set org.gnome.desktop.interface enable-hot-corners false
LAYOUT

echo ">>> Done!"
EOF

echo ">>> Installation finished. Reboot now."
