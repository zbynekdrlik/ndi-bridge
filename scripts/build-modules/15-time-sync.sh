#!/bin/bash
# Time synchronization configuration module for PTP/NTP

configure_time_sync() {
    log "Configuring time synchronization (PTP/NTP)..."
    
    # Copy systemd service files BEFORE chroot
    mkdir -p /mnt/usb/etc/systemd/system
    for service in ptp4l.service phc2sys.service time-sync-coordinator.service; do
        if [ -f files/systemd/system/$service ]; then
            cp files/systemd/system/$service /mnt/usb/etc/systemd/system/
            log "  Copied $service"
        else
            warn "  $service not found in files/systemd/system/"
        fi
    done
    
    # Create the time sync configuration script that will run in chroot
    cat > /mnt/usb/tmp/configure-time-sync.sh << 'EOFPTP'
#!/bin/bash
set -e

# Install LinuxPTP for high precision time synchronization
apt-get update -qq
apt-get install -y -qq --no-install-recommends linuxptp

# Create PTP configuration directory
mkdir -p /etc/linuxptp

# Create default ptp4l configuration (Layer 2 for bridge compatibility)
cat > /etc/linuxptp/gPTP.cfg << 'EOFGPTP'
[global]
clientOnly		1
domainNumber		0
network_transport	L2
step_threshold		1
first_step_threshold	0.001
time_stamping		software

[eth1]
EOFGPTP

# Create master ptp4l configuration (for systems that should act as master)
cat > /etc/linuxptp/master.cfg << 'EOFMASTER'
[global]
domainNumber		0
network_transport	L2
step_threshold		1
first_step_threshold	0.001
time_stamping		software
serverOnly		1
priority1		10

# Network interface
[eth1]
EOFMASTER

# Systemd service files were copied before chroot
# ptp4l.service and phc2sys.service are now in /etc/systemd/system/

# Create check_clocks utility for verification
cat > /usr/local/bin/check_clocks << 'EOFCHECK'
#!/bin/bash
# Simple script to check if clocks are synchronized

if ! command -v ptp4l &> /dev/null; then
    echo "LinuxPTP is not installed"
    exit 1
fi

# Check if services are running
if systemctl is-active --quiet ptp4l; then
    echo "ptp4l is running"
else
    echo "ptp4l is not running"
    exit 1
fi

if systemctl is-active --quiet phc2sys; then
    echo "phc2sys is running"
else
    echo "phc2sys is not running"
    exit 1
fi

# Check time offset from logs (simple check)
# In a production environment, you would want more sophisticated checking
echo "Clock synchronization services are running"
echo "For detailed offset information, check logs with: journalctl -u ptp4l -u phc2sys"
EOFCHECK

chmod +x /usr/local/bin/check_clocks

# Create safe PTP startup scripts that use software timestamping when hardware unavailable
cat > /usr/local/bin/ptp4l-safe-start << 'EOFPTPSAFE'
#!/bin/bash
# Safe PTP4L startup that uses software timestamping as fallback

# Use eth0 directly (PTP requires physical interface, not bridge)
IFACE="eth0"
if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "Interface $IFACE not found for PTP"
    exit 1
fi

# Always use Layer 2 transport for bridge compatibility
# Check if interface supports hardware timestamping
if ethtool -T "$IFACE" 2>/dev/null | grep -q "hardware-transmit"; then
    echo "Starting PTP4L on interface $IFACE with hardware timestamping in client-only mode (Layer 2)"
    exec /usr/sbin/ptp4l -i "$IFACE" -f /etc/linuxptp/gPTP.cfg --step_threshold=1 -2 -s -m
else
    echo "Interface $IFACE does not support hardware timestamping, using software timestamping in client-only mode (Layer 2)"
    exec /usr/sbin/ptp4l -i "$IFACE" -f /etc/linuxptp/gPTP.cfg --step_threshold=1 -2 -S -s -m
fi
EOFPTPSAFE

cat > /usr/local/bin/phc2sys-safe-start << 'EOFPHCSAFE'
#!/bin/bash
# Safe PHC2SYS startup for software timestamping mode

# Wait for PTP4L to establish
sleep 10

# Check if PTP4L is running
if ! pgrep -f "ptp4l" >/dev/null; then
    echo "PTP4L not running - PHC2SYS not needed"
    exit 0
fi

# For software timestamping mode, sync system clock from PTP4L
echo "Starting PHC2SYS in software timestamping mode"
exec /usr/sbin/phc2sys -a -r --step_threshold=1 -m
EOFPHCSAFE

chmod +x /usr/local/bin/ptp4l-safe-start
chmod +x /usr/local/bin/phc2sys-safe-start

# Enable services
systemctl enable ptp4l
systemctl enable phc2sys

# Also install NTP as fallback
apt-get install -y -qq --no-install-recommends chrony || echo "Warning: chrony installation failed"

# Configure chrony as fallback
cat > /etc/chrony/chrony.conf << 'EOFCHRONY'
pool ntp.ubuntu.com        iburst maxsources 4
pool 0.ubuntu.pool.ntp.org iburst maxsources 1
pool 1.ubuntu.pool.ntp.org iburst maxsources 1
pool 2.ubuntu.pool.ntp.org iburst maxsources 2

# Allow NTP client access over network
allow

# Serve time even if not synchronized
local stratum 10

# Use RTC as additional time source
rtcsync

# Enable hardware timestamping if available
# hwtimestamp *

# Log files
logdir /var/log/chrony

# Reduce minimum number of selectable sources
minsources 2
EOFCHRONY

# Install but DO NOT auto-enable chrony - it will be managed by coordination script
# systemctl enable chrony || echo "Warning: chronyd service not available, trying chronyd"
# systemctl enable chronyd 2>/dev/null || true
echo "Chrony installed but not enabled - will be managed by PTP coordination"

# time-sync-coordinator.service was copied before chroot

# Create coordination script
cat > /usr/local/bin/time-sync-coordinator << 'EOFCOORDSCRIPT'
#!/bin/bash
# PTP/NTP Coordination Service
# Disables NTP when PTP is synchronized, enables NTP as fallback when PTP fails

LOG_TAG="time-sync-coordinator"
PTP_SYNC_THRESHOLD=0.1    # 100µs - consider PTP synchronized if offset < 100µs
CHECK_INTERVAL=60         # Check every 60 seconds

log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LOG_TAG] $1"
    logger -t "$LOG_TAG" "$1"
}

is_ptp_synchronized() {
    # Check if ptp4l service is running
    if ! systemctl is-active ptp4l >/dev/null 2>&1; then
        return 1
    fi
    
    # Check recent PTP logs for synchronization
    local ptp_log=$(journalctl -u ptp4l -n 10 --no-pager -o cat 2>/dev/null | grep "master offset" | tail -1)
    
    if [[ -z "$ptp_log" ]]; then
        return 1
    fi
    
    # Extract offset in nanoseconds and check if within threshold
    local offset_ns=$(echo "$ptp_log" | awk '{print $4}' | tr -d '-')
    local offset_ms=$(echo "$offset_ns" | awk '{printf "%.6f", $1/1000000}')
    
    # Check if offset is within threshold (less than 1ms)
    if awk -v offset="$offset_ms" -v thresh="$PTP_SYNC_THRESHOLD" 'BEGIN { exit (offset < thresh) ? 0 : 1 }'; then
        log_msg "PTP synchronized: offset ${offset_ms}ms (< ${PTP_SYNC_THRESHOLD}ms)"
        return 0
    else
        log_msg "PTP offset too high: ${offset_ms}ms (> ${PTP_SYNC_THRESHOLD}ms)"
        return 1
    fi
}

is_dante_mode() {
    # Check if Dante/Statime service is running (indicates Dante mode)
    if systemctl is-active statime >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

manage_services() {
    # Skip management if in Dante mode - let Statime handle PTP
    if is_dante_mode; then
        log_msg "Dante mode active - skipping PTP management"
        # Stop our PTP services to avoid conflicts
        systemctl stop ptp4l 2>/dev/null || true
        systemctl stop phc2sys 2>/dev/null || true
        return
    fi
    
    if is_ptp_synchronized; then
        # PTP is working well - disable NTP
        if systemctl is-active chrony >/dev/null 2>&1 || systemctl is-active chronyd >/dev/null 2>&1; then
            log_msg "PTP synchronized - disabling NTP services"
            systemctl stop chrony 2>/dev/null || true
            systemctl stop chronyd 2>/dev/null || true
        fi
    else
        # PTP is not synchronized - enable NTP as fallback
        if ! systemctl is-active chrony >/dev/null 2>&1 && ! systemctl is-active chronyd >/dev/null 2>&1; then
            log_msg "PTP not synchronized - enabling NTP as fallback"
            systemctl start chrony 2>/dev/null || systemctl start chronyd 2>/dev/null || true
        fi
    fi
}

log_msg "Starting PTP/NTP coordination service"

while true; do
    manage_services
    sleep $CHECK_INTERVAL
done
EOFCOORDSCRIPT

chmod +x /usr/local/bin/time-sync-coordinator

# Enable the coordination service
systemctl enable time-sync-coordinator

echo "Time synchronization coordination configured"
echo "Time synchronization configuration completed"
EOFPTP

    chmod +x /mnt/usb/tmp/configure-time-sync.sh
    
    # Add the time sync configuration execution to the main configure-system.sh
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFTIMESYNC'

# Execute time synchronization configuration
echo "Configuring time synchronization..."
/tmp/configure-time-sync.sh
EOFTIMESYNC
}

export -f configure_time_sync
