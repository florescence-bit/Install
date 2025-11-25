#!/bin/bash
set -e

SUMMARY="/root/installation-summary.txt"
echo "=== Arch Linux Installation Summary ===" > $SUMMARY
echo "Start Time: $(date)" >> $SUMMARY

DISK=/dev/nvme0n1

echo ">>> Partitioning Disk"
{
sgdisk -Z $DISK
sgdisk -n 1:0:+500M -t 1:ef00 $DISK
sgdisk -n 2:0:+150G -t 2:8300 $DISK
sgdisk -n 3:0:0     -t 3:8300 $DISK
} >> $SUMMARY

echo ">>> Formatting Partitions"
{
mkfs.vfat -F32 ${DISK}p1
mkfs.ext4 ${DISK}p2
mkfs.ext4 ${DISK}p3
} >> $SUMMARY

echo ">>> Mounting"
{
mount ${DISK}p2 /mnt
mkdir /mnt/efi
mkdir /mnt/home
mount ${DISK}p1 /mnt/efi
mount ${DISK}p3 /mnt/home
} >> $SUMMARY

echo ">>> Installing Base System"
pacstrap /mnt base linux linux-firmware intel-ucode networkmanager sudo nano git pipewire pipewire-alsa pipewire-pulse pipewire-jack >> $SUMMARY

echo ">>> Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo ">>> Entering Chroot"
arch-chroot /mnt /bin/bash << "EOF"

SUMMARY="/root/installation-summary.txt"

echo ">>> Setting timezone" >> \$SUMMARY
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

echo ">>> Locale setup" >> \$SUMMARY
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo ">>> Hostname setup" >> \$SUMMARY
echo "arch" > /etc/hostname

echo ">>> NetworkManager enabled" >> \$SUMMARY
systemctl enable NetworkManager

echo ">>> Creating user 'san'" >> \$SUMMARY
useradd -m -G wheel san

echo "san:san" | chpasswd   # Auto password set

# Allow sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo ">>> Installing GNOME + Extensions" >> \$SUMMARY
pacman --noconfirm -S gnome gnome-tweaks gnome-shell-extensions \
bluez bluez-utils xorg-xwayland

systemctl enable gdm

echo ">>> Installing systemd-boot" >> \$SUMMARY
bootctl install

ROOT_UUID=\$(blkid -s UUID -o value /dev/nvme0n1p2)

cat << BOOT > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=UUID=\$ROOT_UUID rw
BOOT

echo "default arch" > /boot/loader/loader.conf

echo ">>> Preparing macOS theme autoinstall" >> \$SUMMARY
mkdir -p /home/san/.config/autostart
cat << THEMESCRIPT > /home/san/install-theme.sh
#!/bin/bash
cd ~
git clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git
git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git
git clone https://github.com/vinceliuice/WhiteSur-cursors.git

cd WhiteSur-gtk-theme
./install.sh --theme blue --icon blue --normal --round

cd ../WhiteSur-icon-theme
./install.sh

cd ../WhiteSur-cursors
sudo ./install.sh

gsettings set org.gnome.desktop.interface gtk-theme "WhiteSur-light-blue"
gsettings set org.gnome.desktop.interface icon-theme "WhiteSur"
gsettings set org.gnome.desktop.interface cursor-theme "WhiteSur-cursors"

rm -f ~/install-theme.sh
rm -f ~/.config/autostart/theme.desktop
THEMESCRIPT

chmod +x /home/san/install-theme.sh
chown san:san /home/san/install-theme.sh

cat << AUTOSTART > /home/san/.config/autostart/theme.desktop
[Desktop Entry]
Type=Application
Exec=/home/san/install-theme.sh
X-GNOME-Autostart-enabled=true
Name=Theme Installer
AUTOSTART

chown san:san /home/san/.config/autostart/theme.desktop

echo ">>> Chroot Configuration Done" >> \$SUMMARY
EOF

echo "End Time: $(date)" >> $SUMMARY
echo ">>> INSTALLATION COMPLETE — Summary saved to /root/installation-summary.txt"
echo ">>> REBOOT NOW"
