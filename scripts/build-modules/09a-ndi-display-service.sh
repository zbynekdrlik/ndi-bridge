#!/bin/bash
# NDI Display service configuration module - Single stream per display design

configure_ndi_display_service() {
    log "Configuring NDI Display service (single-stream design)..."
    
    # Copy NDI Display binary BEFORE chroot (so it's accessible)
    if [ -f build/bin/ndi-display ]; then
        mkdir -p /mnt/usb/opt/ndi-bridge
        cp build/bin/ndi-display /mnt/usb/opt/ndi-bridge/
        chmod +x /mnt/usb/opt/ndi-bridge/ndi-display
        log "  Copied ndi-display binary"
    else
        warn "  ndi-display binary not found at build/bin/ndi-display"
        warn "  Display support will not be available"
        return 0
    fi
    
    # Copy display policy configuration
    if [ -f scripts/config/display-policy.conf ]; then
        mkdir -p /mnt/usb/etc/ndi-bridge
        cp scripts/config/display-policy.conf /mnt/usb/etc/ndi-bridge/
        log "  Copied display-policy.conf"
    fi
    
    # Everything else happens inside chroot
    chroot /mnt/usb /bin/bash << 'EOFNDIDISPLAY'
set -e

# Display-related Directories
mkdir -p /etc/ndi-bridge
mkdir -p /var/run/ndi-display

# Systemd service for NDI Display (per-display instance)
cat > /etc/systemd/system/ndi-display@.service << 'EOFSERVICE'
[Unit]
Description=NDI Display Output %i
After=network.target
Wants=ndi-display-monitor.service
Before=getty@tty%i.service
Conflicts=getty@tty%i.service

[Service]
Type=simple
Restart=on-failure
RestartSec=5
User=root

# Environment for display selection
Environment="DISPLAY_ID=%i"
Environment="LD_LIBRARY_PATH=/usr/local/lib"

# Read stream configuration from file
EnvironmentFile=-/etc/ndi-bridge/display-%i.conf

# Start NDI display using launcher script (handles spaces in stream names)
ExecStartPre=/usr/local/bin/ndi-display-console-check %i
ExecStart=/usr/local/bin/ndi-display-launcher %i
ExecStopPost=/usr/bin/rm -f /var/run/ndi-display/display-%i.status

# Resource limits
LimitNOFILE=65536
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=50

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ndi-display-%i

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Monitor service to track display status
cat > /etc/systemd/system/ndi-display-monitor.service << 'EOFMONITOR'
[Unit]
Description=NDI Display Status Monitor
After=network.target

[Service]
Type=simple
Restart=always
RestartSec=10
ExecStart=/usr/local/bin/ndi-display-monitor

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFMONITOR

# Create symlink for convenience
ln -sf /opt/ndi-bridge/ndi-display /usr/local/bin/ndi-display 2>/dev/null || true

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

EOFNDIDISPLAY

    log "NDI Display service configuration complete"
}

export -f configure_ndi_display_service