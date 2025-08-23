#!/bin/bash
# Intercom service configuration module

configure_intercom_service() {
    log "Configuring VDO.Ninja Intercom service..."
    
    # Copy intercom script
    if [ -f scripts/helper-scripts/ndi-bridge-intercom ]; then
        cp scripts/helper-scripts/ndi-bridge-intercom /mnt/usb/opt/ndi-bridge/
        chmod +x /mnt/usb/opt/ndi-bridge/ndi-bridge-intercom
        log "Intercom script copied"
    else
        log "WARNING: ndi-bridge-intercom script not found"
    fi
    
    # Copy intercom helper scripts
    for script in ndi-bridge-intercom-status ndi-bridge-intercom-logs \
                  ndi-bridge-intercom-restart ndi-bridge-intercom-enable \
                  ndi-bridge-intercom-disable; do
        if [ -f scripts/helper-scripts/$script ]; then
            cp scripts/helper-scripts/$script /mnt/usb/opt/ndi-bridge/
            chmod +x /mnt/usb/opt/ndi-bridge/$script
            log "Helper script $script copied"
        fi
    done
    
    # Copy config file
    if [ -f scripts/helper-scripts/intercom.conf ]; then
        mkdir -p /mnt/usb/etc/ndi-bridge
        cp scripts/helper-scripts/intercom.conf /mnt/usb/etc/ndi-bridge/
        log "Intercom config copied"
    else
        log "WARNING: intercom.conf not found"
    fi
    
    # Copy systemd service file
    if [ -f scripts/helper-scripts/ndi-bridge-intercom.service ]; then
        cp scripts/helper-scripts/ndi-bridge-intercom.service /mnt/usb/etc/systemd/system/
        log "Intercom service file copied"
    else
        log "WARNING: ndi-bridge-intercom.service not found"
    fi
    
    # Add to chroot configuration script
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFINTERCOM'

# Enable intercom service
systemctl daemon-reload
systemctl enable ndi-bridge-intercom.service
log "Intercom service enabled"

# Create symlinks for helper scripts
for script in ndi-bridge-intercom-status ndi-bridge-intercom-logs \
              ndi-bridge-intercom-restart ndi-bridge-intercom-enable \
              ndi-bridge-intercom-disable; do
    if [ -f /opt/ndi-bridge/$script ]; then
        ln -sf /opt/ndi-bridge/$script /usr/local/bin/$script
    fi
done

EOFINTERCOM
    
    log "Intercom service configuration complete"
}

# Run the configuration
configure_intercom_service