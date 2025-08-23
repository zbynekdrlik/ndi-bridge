#!/bin/bash
# Power failure resistance and system optimization module
# This module adds the missing features from the monolithic version

configure_power_resistance() {
    log "Configuring power failure resistance and optimizations..."
    
    # Copy systemd config files BEFORE chroot
    mkdir -p /mnt/usb/etc/systemd/system.conf.d
    if [ -f files/systemd/system.conf.d/10-timeout.conf ]; then
        cp files/systemd/system.conf.d/10-timeout.conf /mnt/usb/etc/systemd/system.conf.d/
        log "  Copied systemd timeout configuration"
    else
        warn "  10-timeout.conf not found in files/systemd/system.conf.d/"
    fi
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFPOWER'

# Configure system for power failure resistance

# Reduce swappiness for better performance
echo "vm.swappiness=10" >> /etc/sysctl.conf

# Systemd timeout config was copied before chroot

# Create helper scripts for filesystem remounting
cat > /usr/local/bin/ndi-bridge-rw << 'EOFRW'
#!/bin/bash
mount -o remount,rw /
echo "Filesystem mounted read-write. Use 'ndi-bridge-ro' to return to read-only."
EOFRW
chmod +x /usr/local/bin/ndi-bridge-rw

cat > /usr/local/bin/ndi-bridge-ro << 'EOFRO'
#!/bin/bash
sync
mount -o remount,ro /
echo "Filesystem mounted read-only."
EOFRO
chmod +x /usr/local/bin/ndi-bridge-ro

# Update the info script to show filesystem status
sed -i '/^echo "Filesystem Status:"/a mount | grep " / " | grep -q "ro" && echo "Root: read-only (protected)" || echo "Root: read-write (UNSAFE)"' /usr/local/bin/ndi-bridge-info 2>/dev/null || true

# Add ro/rw commands to help
sed -i '/ndi-bridge-netmon/a echo "  ndi-bridge-rw           - Mount filesystem read-write (for maintenance)"\necho "  ndi-bridge-ro           - Mount filesystem read-only (default)"' /usr/local/bin/ndi-bridge-help 2>/dev/null || true

EOFPOWER
}

# Configure read-only root filesystem
configure_readonly_root() {
    log "Configuring read-only root filesystem..."
    
    # This needs to be done after chroot, so we add it to the end of configure-system.sh
    # Determine the correct root partition device outside heredoc
    if [[ $USB_DEVICE == /dev/loop* ]]; then
        ROOT_PARTITION="/dev/mapper/$(basename $USB_DEVICE)p2"
    else
        ROOT_PARTITION="${USB_DEVICE}2"
    fi
    
    cat >> /mnt/usb/tmp/configure-system.sh << EOFREADONLY

# Configure filesystem for read-only operation
# First update fstab to mount root as read-only
ROOT_UUID=\$(blkid -s UUID -o value $ROOT_PARTITION)
sed -i "s|UUID=.* / ext4 .*|UUID=\$ROOT_UUID / ext4 ro,noatime,errors=remount-ro 0 1|" /etc/fstab

# DO NOT enable remount-rw service - it breaks power failure protection!
# The service exists for emergency use only and must remain disabled
# Filesystem should boot read-only as specified in fstab
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable remount-rw.service 2>/dev/null || true
else
    update-rc.d remount-rw disable 2>/dev/null || true
fi

EOFREADONLY
}

# Post-chroot filesystem tuning
tune_filesystem() {
    log "Tuning filesystem for power failure resistance..."
    
    # This runs outside chroot after setup is complete
    # Enable journal data mode for better power failure resistance
    tune2fs -o journal_data ${USB_DEVICE}3 2>/dev/null || true
    
    # Set filesystem to check every 30 mounts or 180 days
    tune2fs -c 30 -i 180 ${USB_DEVICE}3 2>/dev/null || true
}

export -f configure_power_resistance
export -f configure_readonly_root
export -f tune_filesystem