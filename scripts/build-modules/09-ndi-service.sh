#!/bin/bash
# NDI service configuration module

configure_ndi_service() {
    log "Configuring NDI Bridge service..."
    
    # Copy NDI Capture binary BEFORE chroot (so it's accessible)
    if [ -f build/bin/ndi-capture ]; then
        mkdir -p /mnt/usb/opt/ndi-bridge
        cp build/bin/ndi-capture /mnt/usb/opt/ndi-bridge/
        chmod +x /mnt/usb/opt/ndi-bridge/ndi-capture
        log "NDI Capture binary copied"
    else
        log "ERROR: ndi-capture binary not found at build/bin/ndi-capture"
        exit 1
    fi
    
    # Copy systemd service files BEFORE chroot
    mkdir -p /mnt/usb/etc/systemd/system
    for service in ndi-capture.service setup-logs.service ndi-bridge-collector.service; do
        if [ -f files/systemd/system/$service ]; then
            cp files/systemd/system/$service /mnt/usb/etc/systemd/system/
            log "  Copied $service"
        else
            warn "  $service not found in files/systemd/system/"
        fi
    done
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFNDI'

# Create NDI directories
mkdir -p /opt/ndi-bridge /etc/ndi-bridge

# Save build information
echo "BUILD_TIMESTAMP_PLACEHOLDER" > /etc/ndi-bridge/build-timestamp
echo "BUILD_SCRIPT_VERSION_PLACEHOLDER" > /etc/ndi-bridge/build-script-version

# NDI configuration - default to "USB Capture"
cat > /etc/ndi-bridge/config << EOFCONFIG
DEVICE="/dev/video0"
NDI_NAME="USB Capture"
EOFCONFIG

# NDI runner script
cat > /opt/ndi-bridge/run.sh << 'EOFRUN'
#!/bin/bash
source /etc/ndi-bridge/config
[ -z "$NDI_NAME" ] && NDI_NAME=$(hostname)

# Create log directory if it doesn't exist (tmpfs)
mkdir -p /var/log/ndi-bridge 2>/dev/null || true

# Wait for network
while ! ping -c 1 -W 1 8.8.8.8 &> /dev/null; do
    echo "Waiting for network..."
    sleep 2
done

# Wait for video device
while [ ! -e "$DEVICE" ]; do
    echo "Waiting for $DEVICE..."
    sleep 2
done

# Check time synchronization before starting NDI Bridge
# This ensures optimal frame synchronization quality
check_time_sync() {
    # First try PTP sync check
    if command -v check_clocks &> /dev/null; then
        if check_clocks &> /dev/null; then
            echo "Time synchronization verified via PTP"
            return 0
        fi
    fi
    
    # Fallback to chrony if available
    if command -v chronyc &> /dev/null; then
        if chronyc tracking | grep -q "System time.*within.*offset"; then
            echo "Time synchronization verified via NTP"
            return 0
        fi
    fi
    
    # If we can't verify sync, log a warning but continue
    echo "Warning: Could not verify time synchronization status"
    echo "For optimal NDI frame sync, ensure PTP or NTP is properly configured"
    return 0
}

check_time_sync

# Main loop with restart and logging to tmpfs
while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting NDI Capture: $DEVICE -> $NDI_NAME"
    if [ -w /var/log/ndi-bridge ]; then
        LD_LIBRARY_PATH=/usr/local/lib /opt/ndi-bridge/ndi-capture "$DEVICE" "$NDI_NAME" 2>&1 | tee -a /var/log/ndi-bridge/ndi-capture.log
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDI Capture exited, restarting in 5 seconds..." | tee -a /var/log/ndi-bridge/ndi-capture.log
    else
        LD_LIBRARY_PATH=/usr/local/lib /opt/ndi-bridge/ndi-capture "$DEVICE" "$NDI_NAME" 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDI Capture exited, restarting in 5 seconds..."
    fi
    sleep 5
done
EOFRUN
chmod +x /opt/ndi-bridge/run.sh

# Systemd service files were copied before chroot
# ndi-capture.service is now in /etc/systemd/system/

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable ndi-capture
else
    update-rc.d ndi-capture enable 2>/dev/null || true
fi

# setup-logs.service was copied before chroot

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable setup-logs
else
    update-rc.d setup-logs enable 2>/dev/null || true
fi

# ndi-bridge-collector.service was copied before chroot

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable ndi-bridge-collector
else
    update-rc.d ndi-bridge-collector enable 2>/dev/null || true
fi

EOFNDI
}

export -f configure_ndi_service
