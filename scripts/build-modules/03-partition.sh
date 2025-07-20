#!/bin/bash
# USB partitioning module

partition_usb() {
    log "Partitioning USB device $USB_DEVICE..."
    
    # Unmount any mounted partitions
    umount ${USB_DEVICE}* 2>/dev/null || true
    
    # Clear existing partition table
    dd if=/dev/zero of=$USB_DEVICE bs=1M count=10 2>/dev/null
    sync
    
    # Create GPT partition table
    parted -s $USB_DEVICE mklabel gpt
    
    # Create EFI partition (512MB)
    parted -s $USB_DEVICE mkpart primary fat32 1MiB 513MiB
    parted -s $USB_DEVICE set 1 esp on
    
    # Create root partition (rest of space)
    parted -s $USB_DEVICE mkpart primary ext4 513MiB 100%
    
    # Wait for partitions to appear
    sleep 2
    partprobe $USB_DEVICE
    sleep 2
    
    # Format partitions
    log "Formatting partitions..."
    mkfs.fat -F32 ${USB_DEVICE}1
    mkfs.ext4 -F ${USB_DEVICE}2
    
    log "Partitioning complete"
}

export -f partition_usb