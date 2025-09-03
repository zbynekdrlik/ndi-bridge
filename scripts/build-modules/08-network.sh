#!/bin/bash
# Network configuration module

configure_network() {
    log "Configuring network bridge..."
    
    # Copy avahi service file BEFORE chroot (so it's accessible)
    if [ -f files/avahi/services/media-bridge-http.service ]; then
        mkdir -p /mnt/usb/etc/avahi/services
        cp files/avahi/services/media-bridge-http.service /mnt/usb/etc/avahi/services/
        log "  Copied media-bridge-http.service"
    else
        warn "  media-bridge-http.service not found in files/avahi/services/"
    fi
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFNET'

# Configure network bridge for both ethernet interfaces
mkdir -p /etc/systemd/network

# Create bridge device with no MAC address (inherit from first interface)
cat > /etc/systemd/network/10-br0.netdev << EOFBRIDGE
[NetDev]
Name=br0
Kind=bridge
# Let kernel assign MAC from first enslaved interface
MACAddress=none

[Bridge]
STP=false
EOFBRIDGE

# Create link file to prevent systemd from generating MAC
cat > /etc/systemd/network/10-br0.link << EOFBRLINK
[Match]
OriginalName=br0

[Link]
# Don't generate MAC, use kernel's default behavior
MACAddressPolicy=none
EOFBRLINK

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
# Use DHCP-provided DNS (systemd-resolved will handle fallback)
UseDNS=yes
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
host-name=media-bridge
domain-name=local
use-ipv4=yes
use-ipv6=no
allow-interfaces=br0
deny-interfaces=lo
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=yes

[publish]
publish-aaaa-on-ipv4=no
publish-a-on-ipv6=no
publish-addresses=yes
publish-hinfo=yes
publish-workstation=no
publish-domain=yes
publish-dns-servers=192.168.1.1
publish-resolv-conf-dns-servers=yes

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

# Configure NSS (Name Service Switch) to enable mDNS resolution
# This allows .local hostname resolution
cat > /etc/nsswitch.conf << 'EOFNSS'
# /etc/nsswitch.conf
#
# Name Service Switch configuration file.

passwd:         files systemd
group:          files systemd
shadow:         files

hosts:          files mdns4_minimal [NOTFOUND=return] dns mdns4
networks:       files

protocols:      db files
services:       db files
ethers:         db files
rpc:            db files

netgroup:       nis
EOFNSS

# Avahi services directory is created and service file is copied before chroot
# NOTE: NDI service advertisement is handled by the Media Bridge application itself
# HTTP service advertisement for web interface was copied to /etc/avahi/services/

EOFNET

    # No need for complex MAC generation - kernel handles it automatically!
    # Bridge will inherit MAC from first (or lowest) enslaved interface
}

export -f configure_network
