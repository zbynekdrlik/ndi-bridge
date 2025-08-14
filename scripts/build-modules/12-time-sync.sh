#!/bin/bash
# Time synchronization configuration module for PTP/NTP

configure_time_sync() {
    log "Configuring time synchronization (PTP/NTP)..."
    
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

[eth0]
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
[eth0]
EOFMASTER

# Create ptp4l systemd service
cat > /etc/systemd/system/ptp4l.service << 'EOFPTP4L'
[Unit]
Description=PTPv2 port in slave mode
After=network.target
After=ndi-bridge-network-setup.service

[Service]
Type=simple
ExecStart=/usr/local/bin/ptp4l-safe-start
Restart=on-failure
RestartSec=30
StartLimitBurst=3

# To configure as master, replace gPTP.cfg with master.cfg and restart:
# ExecStart=/usr/sbin/ptp4l -i eth0 -f /etc/linuxptp/master.cfg --step_threshold=1 -m

[Install]
WantedBy=multi-user.target
EOFPTP4L

# Create phc2sys systemd service
cat > /etc/systemd/system/phc2sys.service << 'EOFPHC2SYS'
[Unit]
Description=PHC to system clock synchronization
After=ptp4l.service

[Service]
Type=simple
ExecStart=/usr/local/bin/phc2sys-safe-start
Restart=on-failure
RestartSec=30
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOFPHC2SYS

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

# Enable chrony
systemctl enable chrony || echo "Warning: chronyd service not available, trying chronyd"
systemctl enable chronyd 2>/dev/null || true

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
