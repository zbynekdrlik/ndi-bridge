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
    
    # Create root partition (rest of disk)
    parted -s $USB_DEVICE mkpart primary btrfs 513MiB 100%
    
    # Wait for partitions to appear
    sleep 2
    partprobe $USB_DEVICE 2>/dev/null || true
    
    # Create partition mappings using kpartx (needed for WSL/loop devices)
    log "Creating partition mappings..."
    kpartx -av $USB_DEVICE
    sleep 2
    
    # Determine partition device names
    if [[ $USB_DEVICE == /dev/loop* ]]; then
        # For loop devices, use kpartx mappings
        PART1="/dev/mapper/$(basename $USB_DEVICE)p1"
        PART2="/dev/mapper/$(basename $USB_DEVICE)p2"
    else
        # For real USB devices, use standard naming
        PART1="${USB_DEVICE}1"
        PART2="${USB_DEVICE}2"
    fi
    
    # Format partitions
    log "Formatting partitions..."
    mkfs.fat -F32 $PART1  # EFI partition
    # Btrfs with optimizations for flash media and power failure resistance
    mkfs.btrfs -f -L "NDI-BRIDGE" \
        --nodesize 16384 \
        $PART2
    
    log "Partitioning complete"
}

export -f partition_usb