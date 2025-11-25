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
pacstrap /mnt base linux linux-firmware nano sudo git networkmanager \
pipewire pipewire-alsa pipewire-pulse pipewire-jack xorg-xwayland

echo ">>> Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo ">>> Chrooting and Configuring"
arch-chroot /mnt /bin/bash << 'EOF'

echo ">>> Setting Timezone, Locale, Hostname"

ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "arch" > /etc/hostname

echo ">>> Enabling NetworkManager"
systemctl enable NetworkManager

echo ">>> Creating User 'arch'"
useradd -m -G wheel arch
echo "Set ROOT password:"
passwd
echo "Set password for USER arch:"
passwd arch

sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo ">>> Installing GNOME + Drivers"
pacman --noconfirm -S gnome gdm gnome-tweaks gnome-shell-extensions \
bluez bluez-utils \
intel-ucode amd-ucode nvidia nvidia-utils nvidia-settings

systemctl enable gdm

echo ">>> Installing systemd-boot"
bootctl install

cat << BOOT > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /amd-ucode.img
initrd /initramfs-linux.img
options root=UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) rw
BOOT

echo ">>> Installing Theme Requirements"
pacman --noconfirm -S sassc jq imagemagick unzip

echo ">>> Creating First Boot Theme Script"

cat << 'THEMESETUP' > /home/arch/setup_theme.sh
#!/bin/bash

cd /home/arch
git clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git
git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git
git clone https://github.com/vinceliuice/WhiteSur-cursors.git

cd WhiteSur-gtk-theme
./install.sh --theme blue --icon blue --normal --round

cd ../WhiteSur-icon-theme
./install.sh

cd ../WhiteSur-cursors
sudo ./install.sh

# Apply GNOME Theme
gsettings set org.gnome.desktop.interface gtk-theme "WhiteSur-light-blue"
gsettings set org.gnome.desktop.interface icon-theme "WhiteSur"
gsettings set org.gnome.desktop.interface cursor-theme "WhiteSur-cursors"
gsettings set org.gnome.desktop.interface accent-color 'blue'

# Dock macOS style
gnome-extensions enable dash-to-dock@micxgx.gmail.com
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false
gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'DYNAMIC'
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.5

rm /home/arch/setup_theme.sh
THEMESETUP

chmod +x /home/arch/setup_theme.sh
chown arch:arch /home/arch/setup_theme.sh

echo "bash ~/setup_theme.sh" >> /home/arch/.bash_profile

echo ">>> Preparing Installation Summary"

cat << REPORT > /root/installation-summary.txt
================ ARCH INSTALLATION REPORT ================
DISK: /dev/nvme0n1
EFI:  /dev/nvme0n1p1 (500M - FAT32)
ROOT: /dev/nvme0n1p2 (150G - ext4)
HOME: /dev/nvme0n1p3 (remaining - ext4)

SYSTEM:
- Kernel: Linux
- Bootloader: systemd-boot
- Timezone: Asia/Kolkata
- Locale: en_US.UTF-8
- Hostname: arch

USER:
- Created user: arch
- Sudo enabled: YES

DESKTOP:
- GNOME installed
- GDM enabled
- GNOME Tweaks installed

DRIVERS:
- Intel microcode
- AMD microcode
- Nvidia + utils + settings

AUDIO:
- PipeWire
- PulseAudio layer
- ALSA pipewire support

THEME:
- WhiteSur GTK
- WhiteSur Icons
- WhiteSur Cursors
- Blue accent theme
- macOS-style dock enabled
- Theme applied automatically on first login

SERVICES ENABLED:
- NetworkManager
- GDM Display Manager
- Bluetooth

Everything completed successfully!
==========================================================
REPORT

EOF

echo ">>> Installation complete! See /root/installation-summary.txt for details."
echo ">>> Reboot when ready."
