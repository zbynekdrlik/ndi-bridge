#!/bin/bash
# Network configuration module

configure_network() {
    log "Configuring network bridge..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFNET'

# Configure network bridge for both ethernet interfaces
mkdir -p /etc/systemd/network

# Create bridge device
cat > /etc/systemd/network/10-br0.netdev << EOFBRIDGE
[NetDev]
Name=br0
Kind=bridge

[Bridge]
STP=false
EOFBRIDGE

# Configure physical interfaces to join bridge
cat > /etc/systemd/network/20-eth.network << EOFETH
[Match]
Name=en*
Name=eth*

[Network]
Bridge=br0
EOFETH

# Configure bridge for DHCP
cat > /etc/systemd/network/30-br0.network << EOFBR0
[Match]
Name=br0

[Network]
DHCP=yes
IPForward=yes

[DHCP]
RouteMetric=10
UseDomains=yes
EOFBR0

# Enable services (use different methods based on what's available)
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable systemd-networkd 2>/dev/null || true
    systemctl enable systemd-resolved 2>/dev/null || true
    # Enable Avahi for NDI discovery
    systemctl enable avahi-daemon 2>/dev/null || true
else
    # Use update-rc.d as fallback for sysvinit
    update-rc.d systemd-networkd enable 2>/dev/null || true
    update-rc.d systemd-resolved enable 2>/dev/null || true
    update-rc.d avahi-daemon enable 2>/dev/null || true
fi

# Configure Avahi to work on our bridge
mkdir -p /etc/avahi
cat > /etc/avahi/avahi-daemon.conf << 'EOFAVAHI'
[server]
use-ipv4=yes
use-ipv6=yes
allow-interfaces=br0
deny-interfaces=lo
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=yes

[publish]
publish-addresses=yes
publish-hinfo=yes
publish-workstation=no
publish-domain=yes

[reflector]
enable-reflector=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
EOFAVAHI

EOFNET
}

export -f configure_network