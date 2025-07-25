#!/bin/bash
# Filesystem and bootloader configuration module

configure_filesystem() {
    log "Configuring filesystem and bootloader..."
    
    # Get UUIDs BEFORE creating the script
    local UUID_ROOT=$(blkid -s UUID -o value ${USB_DEVICE}2)
    local UUID_EFI=$(blkid -s UUID -o value ${USB_DEVICE}1)
    
    cat >> /mnt/usb/tmp/configure-system.sh << EOFFS

# Configure fstab with tmpfs for volatile directories
cat > /etc/fstab << EOFFSTAB
# /etc/fstab: static file system information
UUID=$UUID_ROOT / ext4 errors=remount-ro 0 1
UUID=$UUID_EFI /boot/efi vfat umask=0077 0 1
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
tmpfs /var/log tmpfs defaults,nosuid,nodev,size=100M 0 0
tmpfs /var/tmp tmpfs defaults,nosuid,nodev 0 0
EOFFSTAB

# Install GRUB for both UEFI and legacy BIOS
echo "Installing GRUB bootloader..."

# Install GRUB (UEFI only, matching obsolete script)
echo "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=NDIBRIDGE --removable 2>&1 | head -50

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

echo "Updating GRUB configuration..."
update-grub 2>&1 | head -20

# Update initramfs for all kernels
echo "Updating initramfs..."
update-initramfs -u -k all 2>&1 | head -20

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