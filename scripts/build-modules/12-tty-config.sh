#!/bin/bash
# TTY configuration module

configure_ttys() {
    log "Configuring TTY consoles..."
    
    # Copy systemd service files and overrides BEFORE chroot
    mkdir -p /mnt/usb/etc/systemd/system
    if [ -f files/systemd/system/ndi-logs@.service ]; then
        cp files/systemd/system/ndi-logs@.service /mnt/usb/etc/systemd/system/
        log "  Copied ndi-logs@.service"
    else
        warn "  ndi-logs@.service not found in files/systemd/system/"
    fi
    
    # Copy getty override for TTY2
    mkdir -p /mnt/usb/etc/systemd/system/getty@tty2.service.d
    if [ -f files/systemd/system/getty@tty2.service.d/override.conf ]; then
        cp files/systemd/system/getty@tty2.service.d/override.conf /mnt/usb/etc/systemd/system/getty@tty2.service.d/
        log "  Copied getty@tty2 override"
    else
        warn "  getty@tty2 override not found"
    fi
    
    # Copy getty override for TTY3-6
    for tty in 3 4 5 6; do
        mkdir -p /mnt/usb/etc/systemd/system/getty@tty${tty}.service.d
        if [ -f files/systemd/system/getty@tty.service.d/override.conf ]; then
            cp files/systemd/system/getty@tty.service.d/override.conf /mnt/usb/etc/systemd/system/getty@tty${tty}.service.d/
        fi
    done
    log "  Copied getty overrides for TTY3-6"
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFTTY'

# ndi-logs@.service was copied before chroot

# Disable getty on tty1 and enable our service
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable getty@tty1
    systemctl enable ndi-logs@tty1
else
    update-rc.d getty@tty1 disable 2>/dev/null || true
    update-rc.d ndi-logs@tty1 enable 2>/dev/null || true
fi

# getty@tty2 override was copied before chroot

# Getty overrides for TTY3-6 were copied before chroot
# Enable getty services for TTY3-6
for tty in 3 4 5 6; do
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable getty@tty${tty}
    else
        update-rc.d getty@tty${tty} enable 2>/dev/null || true
    fi
done

# Enable TTY2 only (TTY1 uses ndi-logs service)
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable getty@tty2
else
    update-rc.d getty@tty2 enable 2>/dev/null || true
fi

# Create .profile that shows welcome
cat > /root/.profile << 'EOFPROFILE'
# Set TERM for TTY
export TERM=linux

# Run welcome in auto-refresh mode
/usr/local/bin/media-bridge-welcome-loop
EOFPROFILE

# All helper scripts (welcome, show-logs, welcome-loop) are installed from
# helper-scripts directory - don't create them inline here!
# Just ensure they're executable
chmod +x /usr/local/bin/media-bridge-show-logs 2>/dev/null || true
chmod +x /usr/local/bin/media-bridge-welcome 2>/dev/null || true
chmod +x /usr/local/bin/media-bridge-welcome-loop 2>/dev/null || true

# Old inline scripts have been completely removed.
# All scripts are now maintained in scripts/helper-scripts/ directory

EOFTTY
}

export -f configure_ttys
