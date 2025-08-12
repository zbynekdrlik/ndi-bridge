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

# Create default ptp4l configuration (gPTP profile)
cat > /etc/linuxptp/gPTP.cfg << 'EOFGPTP'
[global]
# Slave mode by default - synchronize to network master
GMCapable		0
Priority1		248
Priority2		248
clockClass		248
clockAccuracy		0xFE
offsetScaledLogVariance	0xFFFF
domainNumber		0
network_transport	UDPv4

# Network interface (will be auto-detected in most cases)
[eth0]
EOFGPTP

# Create master ptp4l configuration (for systems that should act as master)
cat > /etc/linuxptp/master.cfg << 'EOFMASTER'
[global]
# Master mode - act as grandmaster clock
GMCapable		1
Priority1		128
Priority2		128
clockClass		6
slaveOnly		0
domainNumber		0
network_transport	UDPv4

# Network interface
[eth0]
EOFMASTER

# Create ptp4l systemd service
cat > /etc/systemd/system/ptp4l.service << 'EOFPTP4L'
[Unit]
Description=PTPv2 port in slave mode
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/ptp4l -i eth0 -f /etc/linuxptp/gPTP.cfg --step_threshold=1 -m
Restart=always
RestartSec=5

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
ExecStart=/usr/sbin/phc2sys -s eth0 -c CLOCK_REALTIME --step_threshold=1 --transportSpecific=1 -w -m
Restart=always
RestartSec=5

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
}

export -f configure_time_sync
