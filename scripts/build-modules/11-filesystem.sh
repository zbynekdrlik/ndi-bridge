#!/bin/bash
# Filesystem and bootloader configuration module

configure_filesystem() {
    log "Configuring filesystem and bootloader..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFFS'

# Configure fstab with tmpfs for volatile directories
cat > /etc/fstab << EOFFSTAB
# /etc/fstab: static file system information
UUID=$(blkid -s UUID -o value ${USB_DEVICE}2) / ext4 errors=remount-ro 0 1
UUID=$(blkid -s UUID -o value ${USB_DEVICE}1) /boot/efi vfat umask=0077 0 1
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
tmpfs /var/log tmpfs defaults,nosuid,nodev,size=100M 0 0
tmpfs /var/tmp tmpfs defaults,nosuid,nodev 0 0
EOFFSTAB

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu

# Configure GRUB with custom theme and colors
cat > /etc/default/grub << EOFGRUB
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="NDI Bridge"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL_OUTPUT="console"
EOFGRUB

# Custom GRUB colors
mkdir -p /boot/grub
cat > /boot/grub/custom.cfg << 'EOFGRUBCUSTOM'
set color_normal=white/black
set color_highlight=black/green
set menu_color_normal=white/black
set menu_color_highlight=black/green
EOFGRUBCUSTOM

update-grub

# Configure systemd for read-only root (prepare for future)
cat > /etc/systemd/system/remount-rw.service << EOFREMOUNT
[Unit]
Description=Remount root filesystem read-write
Before=local-fs-pre.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/mount -o remount,rw /
RemainAfterExit=yes

[Install]
WantedBy=local-fs-pre.target
EOFREMOUNT

# For now, keep it read-write but ready for read-only conversion
# systemctl enable remount-rw

EOFFS
}

export -f configure_filesystem