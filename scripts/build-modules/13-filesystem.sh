#!/bin/bash
# Filesystem and bootloader configuration module

configure_filesystem() {
    log "Configuring filesystem and bootloader..."
    
    
    # Determine partition device names (same logic as partition script)
    if [[ $USB_DEVICE == /dev/loop* ]]; then
        # For loop devices, use kpartx mappings
        local PART1="/dev/mapper/$(basename $USB_DEVICE)p1"
        local PART2="/dev/mapper/$(basename $USB_DEVICE)p2"
    else
        # For real USB devices, use standard naming
        local PART1="${USB_DEVICE}1"
        local PART2="${USB_DEVICE}2"
    fi
    
    # Get UUIDs BEFORE creating the script
    local UUID_ROOT=$(blkid -s UUID -o value $PART2)
    local UUID_EFI=$(blkid -s UUID -o value $PART1)
    
    cat >> /mnt/usb/tmp/configure-system.sh << EOFFS

# Configure fstab with Btrfs optimized for power failure resistance and fast boot
cat > /etc/fstab << EOFFSTAB
# /etc/fstab: static file system information
# Btrfs mount options:
# - noatime: reduce unnecessary writes
# - ssd: optimize for SSD/flash storage
# - space_cache=v2: faster mount times
# - discard=async: background TRIM for flash
# - commit=15: sync to disk every 15 seconds (balance between safety and performance)
# - no compression for faster boot
UUID=$UUID_ROOT / btrfs defaults,noatime,ssd,space_cache=v2,discard=async,commit=15 0 0
UUID=$UUID_EFI /boot/efi vfat umask=0077 0 1
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
GRUB_DISTRIBUTOR="Media Bridge"
GRUB_CMDLINE_LINUX_DEFAULT="modprobe.blacklist=iwlwifi,iwldvm,iwlmvm,mac80211,cfg80211 net.ifnames=0"
GRUB_CMDLINE_LINUX=""
GRUB_TERMINAL_OUTPUT="console"
# Fix: Disable 30-second delay after improper shutdown/power loss
# Without this, GRUB waits 30 seconds after any unclean shutdown (common in production)
GRUB_RECORDFAIL_TIMEOUT=0
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


EOFFS
}

export -f configure_filesystem