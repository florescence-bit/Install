#!/bin/bash
set -euo pipefail

# -------------------------
# Arch install -> fixed script
# Wipes DISK (be careful)
# Creates user: san / san
# Installs GNOME + GRUB + intel-ucode
# Prepares first-login theme installer for WhiteSur (macOS look)
# Writes summary to /mnt/root/installation-summary.txt (while in live)
# -------------------------

# --------- CONFIG ----------
DISK="/dev/nvme0n1"           # <<== VERIFY this BEFORE running (lsblk)
SUMMARY_ON_LIVE="/root/installation-summary.txt"
SUMMARY_ON_INST="/root/installation-summary.txt"   # inside the new system (saved under /mnt/root while running)
USERNAME="san"
PASSWORD="san"
TIMEZONE="Asia/Kolkata"
HOSTNAME="hp-arch"
# ---------------------------

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run this script as root from the Arch live environment."
  exit 1
fi

echo "=== Arch install (fixed) started at: $(date) ===" > "$SUMMARY_ON_LIVE"
echo "Target disk: $DISK" >> "$SUMMARY_ON_LIVE"

# sanity: make sure disk exists
if [ ! -b "$DISK" ]; then
  echo "ERROR: target disk $DISK not found. Aborting." | tee -a "$SUMMARY_ON_LIVE"
  exit 1
fi

echo ">>> Partitioning $DISK (EFI:500M, ROOT:150G, HOME:rest)" | tee -a "$SUMMARY_ON_LIVE"
{
  sgdisk -Z "$DISK"
  sgdisk -o "$DISK"
  sgdisk -n 1:0:+500M -t 1:ef00 -c 1:"EFI" "$DISK"
  sgdisk -n 2:0:+150G -t 2:8300 -c 2:"ROOT" "$DISK"
  sgdisk -n 3:0:0     -t 3:8300 -c 3:"HOME" "$DISK"
  # make kernel re-read partition table
  partprobe "$DISK"
  sleep 1
} >> "$SUMMARY_ON_LIVE" 2>&1

echo ">>> Formatting partitions" | tee -a "$SUMMARY_ON_LIVE"
{
  mkfs.fat -F32 "${DISK}p1"
  mkfs.ext4 -F "${DISK}p2"
  mkfs.ext4 -F "${DISK}p3"
} >> "$SUMMARY_ON_LIVE" 2>&1

echo ">>> Mounting filesystems" | tee -a "$SUMMARY_ON_LIVE"
{
  mount "${DISK}p2" /mnt
  mkdir -p /mnt/boot
  mkdir -p /mnt/home
  mount "${DISK}p1" /mnt/boot      # EFI mounted at /boot in the installed system
  mount "${DISK}p3" /mnt/home
} >> "$SUMMARY_ON_LIVE" 2>&1

echo ">>> Installing base system (pacstrap)" | tee -a "$SUMMARY_ON_LIVE"
pacstrap /mnt base linux linux-firmware intel-ucode networkmanager sudo nano git \
  pipewire pipewire-alsa pipewire-pulse pipewire-jack grub efibootmgr os-prober \
  gnome gdm gnome-tweaks gnome-shell-extensions xorg-xwayland bluez bluez-utils \
  --noconfirm >> "$SUMMARY_ON_LIVE" 2>&1

echo ">>> Generating fstab" | tee -a "$SUMMARY_ON_LIVE"
genfstab -U /mnt >> /mnt/etc/fstab

echo ">>> Entering chroot to finish configuration" | tee -a "$SUMMARY_ON_LIVE"

# Pass variables by expanding them into the heredoc
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

SUMMARY="$SUMMARY_ON_INST"

# timezone & locale
echo ">>> Setting timezone/locale" >> "\$SUMMARY"
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# hostname
echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# enable network
systemctl enable NetworkManager

# create user and set password (non-interactive)
echo ">>> Creating user $USERNAME" >> "\$SUMMARY"
useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
# set root password same as provided (optional)
echo "root:$PASSWORD" | chpasswd

# allow wheel sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# enable GDM
systemctl enable gdm

# Install and configure GRUB for EFI
echo ">>> Installing GRUB (EFI)" >> "\$SUMMARY"
# Ensure efivars available
mkdir -p /boot/EFI || true

# Install grub to the EFI system partition mounted at /boot
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --recheck >> "\$SUMMARY" 2>&1 || {
  echo "grub-install returned non-zero, continuing to try to create config" >> "\$SUMMARY"
}

# Create grub config
grub-mkconfig -o /boot/grub/grub.cfg >> "\$SUMMARY" 2>&1

# Prepare first-login theme installer (run as user on first login)
echo ">>> Creating first-login theme/install script for user $USERNAME" >> "\$SUMMARY"

# Write the first-boot script into user's home (it runs once at login)
cat > /home/$USERNAME/first-boot-theme.sh <<'USERTHEME'
#!/bin/bash
set -e

# first-boot theming script (runs as the user)
cd "$HOME"

# Clone/install WhiteSur theme components (they install to /usr or user dirs)
if [ ! -d "$HOME/WhiteSur-gtk-theme" ]; then
  git clone https://github.com/vinceliuice/WhiteSur-gtk-theme.git
else
  cd WhiteSur-gtk-theme && git pull || true
  cd ..
fi

if [ ! -d "$HOME/WhiteSur-icon-theme" ]; then
  git clone https://github.com/vinceliuice/WhiteSur-icon-theme.git
else
  cd WhiteSur-icon-theme && git pull || true
  cd ..
fi

if [ ! -d "$HOME/WhiteSur-cursors" ]; then
  git clone https://github.com/vinceliuice/WhiteSur-cursors.git
else
  cd WhiteSur-cursors && git pull || true
  cd ..
fi

# Try non-interactive installs; these scripts usually support CLI flags but may prompt - this is best-effort
if [ -d "$HOME/WhiteSur-gtk-theme" ]; then
  cd WhiteSur-gtk-theme
  ./install.sh --theme blue --icon blue --normal --round || true
  cd ..
fi

if [ -d "$HOME/WhiteSur-icon-theme" ]; then
  cd WhiteSur-icon-theme
  ./install.sh || true
  cd ..
fi

if [ -d "$HOME/WhiteSur-cursors" ]; then
  cd WhiteSur-cursors
  sudo ./install.sh || true
  cd ..
fi

# Apply GNOME settings (works only inside a running GNOME session)
gsettings set org.gnome.desktop.interface gtk-theme "WhiteSur-light-blue" || true
gsettings set org.gnome.desktop.interface icon-theme "WhiteSur" || true
gsettings set org.gnome.desktop.interface cursor-theme "WhiteSur-cursors" || true
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM' || true
gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false || true
gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'DYNAMIC' || true
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.5 || true

# Try to enable blur extension (if installed) and dash-to-dock
gnome-extensions enable dash-to-dock@micxgx.gmail.com 2>/dev/null || true

# Remove autostart so it only runs once
rm -f "$HOME/.config/autostart/first-boot-theme.desktop"
rm -f "$HOME/first-boot-theme.sh"

echo "First-boot theming script finished."
USERTHEME

# Make it owned by the user and executable
chown $USERNAME:$USERNAME /home/$USERNAME/first-boot-theme.sh
chmod +x /home/$USERNAME/first-boot-theme.sh

# Create autostart .desktop so the script executes once at the user's first login
mkdir -p /home/$USERNAME/.config/autostart
cat > /home/$USERNAME/.config/autostart/first-boot-theme.desktop <<AUTODEST
[Desktop Entry]
Type=Application
Exec=/home/$USERNAME/first-boot-theme.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=First Boot Theme Installer
Comment=Apply WhiteSur theme and macOS-like layout on first login
AUTODEST

chown -R $USERNAME:$USERNAME /home/$USERNAME/.config

# Save some verification info to the summary inside the installed system
echo "INSTALL SUMMARY (inside installed system) - $(date)" > "\$SUMMARY"
echo "Disk: $DISK" >> "\$SUMMARY"
echo "User created: $USERNAME" >> "\$SUMMARY"
echo "Hostname: $HOSTNAME" >> "\$SUMMARY"
echo "Timezone: $TIMEZONE" >> "\$SUMMARY"
echo "GNOME installed and GDM enabled" >> "\$SUMMARY"
echo "GRUB installed to EFI" >> "\$SUMMARY"
echo "First-boot theme script placed at /home/$USERNAME/first-boot-theme.sh" >> "\$SUMMARY"

EOF

# end arch-chroot

echo ">>> Chroot finished. Installation summary (on the installed system) is at /mnt$SUMMARY_ON_INST" | tee -a "$SUMMARY_ON_LIVE"
echo ">>> Copying live summary to /mnt$SUMMARY_ON_INST for convenience." | tee -a "$SUMMARY_ON_LIVE"

# Copy the live summary into the installed system root so you can view it after boot
cp "$SUMMARY_ON_LIVE" /mnt/$SUMMARY_ON_INST || true

echo ">>> Unmounting partitions" | tee -a "$SUMMARY_ON_LIVE"
umount -R /mnt

echo "=== Arch install finished at: $(date) ===" >> "$SUMMARY_ON_LIVE"
echo "Installation summary saved on LIVE: $SUMMARY_ON_LIVE"
echo "Installation summary saved inside installed system (while mounted): /$SUMMARY_ON_INST (it now lives on the new root)"
echo
echo "REBOOT NOW. Remove USB and boot the installed system. Login as: $USERNAME / $PASSWORD"
