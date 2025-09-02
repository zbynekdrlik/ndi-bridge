#!/bin/bash
# System optimization module - Btrfs provides power failure resistance

configure_power_resistance() {
    log "Configuring system optimizations..."
    
    # Copy systemd config files BEFORE chroot
    mkdir -p /mnt/usb/etc/systemd/system.conf.d
    if [ -f files/systemd/system.conf.d/10-timeout.conf ]; then
        cp files/systemd/system.conf.d/10-timeout.conf /mnt/usb/etc/systemd/system.conf.d/
        log "  Copied systemd timeout configuration"
    else
        warn "  10-timeout.conf not found in files/systemd/system.conf.d/"
    fi
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFPOWER'

# Configure system optimizations

# Reduce swappiness for better performance
echo "vm.swappiness=10" >> /etc/sysctl.conf

# Systemd timeout config was copied before chroot

EOFPOWER
}

export -f configure_power_resistance