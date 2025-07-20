#!/bin/bash
# Filesystem mounting module

mount_filesystems() {
    log "Mounting filesystems..."
    
    # Create mount point
    mkdir -p /mnt/usb
    
    # Mount root partition (now partition 3)
    mount ${USB_DEVICE}3 /mnt/usb
    
    # Create and mount EFI partition (now partition 2)
    mkdir -p /mnt/usb/boot/efi
    mount ${USB_DEVICE}2 /mnt/usb/boot/efi
    
    log "Filesystems mounted"
}

unmount_all() {
    log "Unmounting filesystems..."
    umount /mnt/usb/boot/efi 2>/dev/null || true
    umount /mnt/usb 2>/dev/null || true
    log "Filesystems unmounted"
}

export -f mount_filesystems unmount_all