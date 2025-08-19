#!/bin/bash
# NDI service configuration module

configure_ndi_service() {
    log "Configuring NDI Bridge service..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFNDI'

# Create NDI directories
mkdir -p /opt/ndi-bridge /etc/ndi-bridge

# Save build information
echo "BUILD_TIMESTAMP_PLACEHOLDER" > /etc/ndi-bridge/build-timestamp
echo "BUILD_SCRIPT_VERSION_PLACEHOLDER" > /etc/ndi-bridge/build-script-version

# NDI configuration
cat > /etc/ndi-bridge/config << 'EOFCONFIG'
DEVICE="/dev/video0"
NDI_NAME=""
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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting NDI Bridge: $DEVICE -> $NDI_NAME"
    if [ -w /var/log/ndi-bridge ]; then
        LD_LIBRARY_PATH=/usr/local/lib /opt/ndi-bridge/ndi-bridge "$DEVICE" "$NDI_NAME" 2>&1 | tee -a /var/log/ndi-bridge/ndi-bridge.log
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDI Bridge exited, restarting in 5 seconds..." | tee -a /var/log/ndi-bridge/ndi-bridge.log
    else
        LD_LIBRARY_PATH=/usr/local/lib /opt/ndi-bridge/ndi-bridge "$DEVICE" "$NDI_NAME" 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDI Bridge exited, restarting in 5 seconds..."
    fi
    sleep 5
done
EOFRUN
chmod +x /opt/ndi-bridge/run.sh

# Systemd service (output to journal only, not console)
cat > /etc/systemd/system/ndi-bridge.service << EOFSERVICE
[Unit]
Description=NDI Bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=/opt/ndi-bridge/run.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable ndi-bridge
else
    update-rc.d ndi-bridge enable 2>/dev/null || true
fi

# Create systemd service to setup log directories on boot
cat > /etc/systemd/system/setup-logs.service << EOFLOGSVC
[Unit]
Description=Setup log directories in tmpfs
Before=ndi-bridge.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/mkdir -p /var/log/ndi-bridge
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFLOGSVC

if command -v systemctl >/dev/null 2>&1; then
    systemctl enable setup-logs
else
    update-rc.d setup-logs enable 2>/dev/null || true
fi

EOFNDI
}

export -f configure_ndi_service
