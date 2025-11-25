#!/bin/bash
set -e

# --- CONFIGURATION ---
DISK="/dev/nvme0n1" # CRITICAL: Ensure this matches your disk name (e.g., use 'lsblk')
SUMMARY="/root/installation-summary.txt"
USERNAME="san"
PASSWORD="san" 
TIMEZONE="Asia/Kolkata" # Delhi, India Timezone
HOSTNAME="hp-arch" 

# --- START ---
echo "=== Arch Linux Installation Summary ===" > $SUMMARY
echo "Start Time: $(date)" >> $SUMMARY
echo "Disk: $DISK" >> $SUMMARY

echo ">>> Partitioning Disk ($DISK)"
# p1: EFI (500M), p2: Root (150G), p3: Home (Remaining)
{
sgdisk -Z $DISK
sgdisk -n 1:0:+500M -t 1:ef00 $DISK
sgdisk -n 2:0:+150G -t 2:8300 $DISK
sgdisk -n 3:0:0     -t 3:8300 $DISK
# --- FIX: Tell the kernel to reread the new partition table immediately ---
partprobe $DISK 
# -------------------------------------------------------------------------
} >> $SUMMARY 2>&1

echo ">>> Formatting Partitions"
{
mkfs.vfat -F32 ${DISK}p1
mkfs.ext4 ${DISK}p2
mkfs.ext4 ${DISK}p3
} >> $SUMMARY 2>&1

echo ">>> Mounting File Systems"
{
mount ${DISK}p2 /mnt
mkdir -p /mnt/boot
mkdir -p /mnt/home
mount ${DISK}p1 /mnt/boot/efi # Location for GRUB EFI
mount ${DISK}p3 /mnt/home
} >> $SUMMARY

echo ">>> Installing Base System & GNOME Components"
pacstrap /mnt base linux linux-firmware intel-ucode networkmanager sudo nano git \
pipewire pipewire-alsa pipewire-pulse pipewire-jack grub efibootmgr mesa >> $SUMMARY 2>&1

echo ">>> Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo ">>> Entering Chroot for System Configuration"
arch-chroot /mnt /bin/bash << EOF

SUMMARY="/root/installation-summary.txt"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"

echo ">>> Setting timezone" >> \$SUMMARY
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo ">>> Locale setup" >> \$SUMMARY
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

echo ">>> Hostname setup" >> \$SUMMARY
echo "$HOSTNAME" > /etc/hostname

echo ">>> NetworkManager enabled" >> \$SUMMARY
systemctl enable NetworkManager

echo ">>> Creating user '$USERNAME'" >> \$SUMMARY
useradd -m -G wheel \$USERNAME
echo "\$USERNAME:\$PASSWORD" | chpasswd 
# Allow sudo for wheel group
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo ">>> Installing GNOME, Extensions, and GDM" >> \$SUMMARY
pacman --noconfirm -S gnome gnome-tweaks gnome-shell-extensions \
bluez bluez-utils xorg-xwayland >> \$SUMMARY 2>&1

systemctl enable gdm

echo ">>> Installing and Configuring GRUB" >> \$SUMMARY
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB >> \$SUMMARY 2>&1
grub-mkconfig -o /boot/grub/grub.cfg >> \$SUMMARY 2>&1

echo ">>> Installing macOS (WhiteSur) Theme" >> \$SUMMARY
# Set up necessary dependencies for theme installation
pacman --noconfirm -S gnome-shell-extensions sassc optipng inkscape >> \$SUMMARY 2>&1

cd /home/\$USERNAME

# Clone themes
git clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git
git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git
git clone https://github.com/vinceliuice/WhiteSur-cursors.git

# Install GTK Theme 
cd WhiteSur-gtk-theme
./install.sh -t all -c dark -n all -i arch -s 220 >> \$SUMMARY 2>&1

# Install Icon Theme
cd ../WhiteSur-icon-theme
./install.sh -t default -s 220 >> \$SUMMARY 2>&1

# Install Cursor Theme
cd ../WhiteSur-cursors
sudo ./install.sh >> \$SUMMARY 2>&1

# Apply the theme settings for the new user 'san'
sudo -u \$USERNAME sh -c "
gsettings set org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark'
gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur'
gsettings set org.gnome.desktop.interface cursor-theme 'WhiteSur-cursors'
gsettings set org.gnome.shell.extensions.user-theme name 'WhiteSur-Dark'
" >> \$SUMMARY 2>&1

echo ">>> Chroot Configuration Done" >> \$SUMMARY
EOF

echo "End Time: $(date)" >> $SUMMARY
echo ">>> INSTALLATION COMPLETE — Summary saved to /mnt/root/installation-summary.txt"
echo ">>> Unmounting filesystems..."

# Clean up mounts
umount -R /mnt
echo ">>> Filesystems unmounted."

echo ">>> REBOOT NOW (type 'reboot')"
# Install GTK Theme (using dark for a modern macOS look)
cd WhiteSur-gtk-theme
./install.sh -t all -c dark -n all -i arch -s 220 >> \$SUMMARY 2>&1

# Install Icon Theme
cd ../WhiteSur-icon-theme
./install.sh -t default -s 220 >> \$SUMMARY 2>&1

# Install Cursor Theme
cd ../WhiteSur-cursors
sudo ./install.sh >> \$SUMMARY 2>&1

# Apply the theme settings for the new user 'san'
sudo -u \$USERNAME sh -c "
gsettings set org.gnome.desktop.interface gtk-theme 'WhiteSur-Dark'
gsettings set org.gnome.desktop.interface icon-theme 'WhiteSur'
gsettings set org.gnome.desktop.interface cursor-theme 'WhiteSur-cursors'
gsettings set org.gnome.shell.extensions.user-theme name 'WhiteSur-Dark'
" >> \$SUMMARY 2>&1

echo ">>> Chroot Configuration Done" >> \$SUMMARY
EOF

echo "End Time: $(date)" >> $SUMMARY
echo ">>> INSTALLATION COMPLETE — Summary saved to /mnt/root/installation-summary.txt"
echo ">>> Unmounting filesystems..."

# Clean up mounts
umount -R /mnt
echo ">>> Filesystems unmounted."

echo ">>> REBOOT NOW (type 'reboot')"
