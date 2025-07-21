#!/bin/bash
# Filesystem mounting module

mount_filesystems() {
    log "Mounting filesystems..."
    
    # Create mount point
    mkdir -p /mnt/usb
    
    # Mount root partition
    mount ${USB_DEVICE}2 /mnt/usb
    
    # Create and mount EFI partition
    mkdir -p /mnt/usb/boot/efi
    mount ${USB_DEVICE}1 /mnt/usb/boot/efi
    
    log "Filesystems mounted"
}

unmount_all() {
    log "Unmounting filesystems..."
    umount /mnt/usb/boot/efi 2>/dev/null || true
    umount /mnt/usb 2>/dev/null || true
    log "Filesystems unmounted"
}

export -f mount_filesystems unmount_all