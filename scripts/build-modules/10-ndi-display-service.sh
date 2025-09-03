#!/bin/bash
# NDI Display service configuration module - Single stream per display design

configure_ndi_display_service() {
    log "Configuring NDI Display service (single-stream design)..."
    
    # Copy NDI Display binary BEFORE chroot (so it's accessible)
    if [ -f build/bin/ndi-display ]; then
        mkdir -p /mnt/usb/opt/media-bridge
        cp build/bin/ndi-display /mnt/usb/opt/media-bridge/
        chmod +x /mnt/usb/opt/media-bridge/ndi-display
        log "  Copied ndi-display binary"
    else
        warn "  ndi-display binary not found at build/bin/ndi-display"
        warn "  Display support will not be available"
        return 0
    fi
    
    # Copy display policy configuration
    if [ -f scripts/config/display-policy.conf ]; then
        mkdir -p /mnt/usb/etc/media-bridge
        cp scripts/config/display-policy.conf /mnt/usb/etc/media-bridge/
        log "  Copied display-policy.conf"
    fi
    
    # Copy systemd service files BEFORE chroot
    mkdir -p /mnt/usb/etc/systemd/system
    for service in ndi-display@.service ndi-display-monitor.service; do
        if [ -f files/systemd/system/$service ]; then
            cp files/systemd/system/$service /mnt/usb/etc/systemd/system/
            log "  Copied $service"
        else
            warn "  $service not found in files/systemd/system/"
        fi
    done
    
    # Everything else happens inside chroot
    chroot /mnt/usb /bin/bash << 'EOFNDIDISPLAY'
set -e

# Display-related Directories
mkdir -p /etc/media-bridge
mkdir -p /var/run/ndi-display

# Systemd service files were copied before chroot
# ndi-display@.service and ndi-display-monitor.service are now in /etc/systemd/system/

# Create symlink for convenience
ln -sf /opt/media-bridge/ndi-display /usr/local/bin/ndi-display 2>/dev/null || true

# Helper Scripts Installation
# ============================
# NOTE: ALL helper scripts are installed from scripts/helper-scripts/ by module 12
# DO NOT CREATE ANY INLINE SCRIPTS HERE - it violates modular architecture!
# The helper scripts directory contains:
#   - ndi-display-status
#   - ndi-display-list
#   - ndi-display-show
#   - ndi-display-stop
#   - ndi-display-auto
#   - ndi-display-config
#   - ndi-display-console-check
#   - ndi-display-console-manager
#   - ndi-display-monitor
# All these scripts are maintained as separate files for modularity.

# Enable monitor service (using systemd preset or manual symlink)
# systemctl isn't available in chroot, create enable symlink manually
ln -sf /etc/systemd/system/ndi-display-monitor.service /etc/systemd/system/multi-user.target.wants/ndi-display-monitor.service

# Enable all display services by default (they check config to decide if they run)
# This eliminates the need for systemctl enable when configuring displays
for i in 0 1 2; do
    ln -sf /etc/systemd/system/ndi-display@.service /etc/systemd/system/multi-user.target.wants/ndi-display@${i}.service
done

EOFNDIDISPLAY

    log "NDI Display service configuration complete"
}

export -f configure_ndi_display_service