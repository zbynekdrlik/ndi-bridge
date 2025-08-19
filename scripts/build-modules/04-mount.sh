#!/bin/bash
# Filesystem mounting module

mount_filesystems() {
    log "Mounting filesystems..."
    
    # Determine partition device names (same logic as partitioning)
    if [[ $USB_DEVICE == /dev/loop* ]]; then
        # For loop devices, use kpartx mappings
        PART1="/dev/mapper/$(basename $USB_DEVICE)p1"
        PART2="/dev/mapper/$(basename $USB_DEVICE)p2"
    else
        # For real USB devices, use standard naming
        PART1="${USB_DEVICE}1"
        PART2="${USB_DEVICE}2"
    fi
    
    # Create mount point
    mkdir -p /mnt/usb
    
    # Mount root partition
    mount $PART2 /mnt/usb
    
    # Create and mount EFI partition
    mkdir -p /mnt/usb/boot/efi
    mount $PART1 /mnt/usb/boot/efi
    
    log "Filesystems mounted"
}

unmount_all() {
    log "Unmounting filesystems..."
    umount /mnt/usb/boot/efi 2>/dev/null || true
    umount /mnt/usb 2>/dev/null || true
    
    # Remove kpartx mappings if using loop device
    if [[ $USB_DEVICE == /dev/loop* ]]; then
        kpartx -d $USB_DEVICE 2>/dev/null || true
    fi
    
    log "Filesystems unmounted"
}

export -f mount_filesystems unmount_all