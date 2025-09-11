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

# Create bridge device that inherits MAC from first interface
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
# Use DHCP-provided DNS (systemd-resolved will handle fallback)
UseDNS=yes
# CRITICAL: Use MAC address for DHCP client ID instead of DUID
# This ensures consistent IP addresses across reboots
ClientIdentifier=mac
# Use link-layer (MAC) for DUID if ever needed
DUIDType=link-layer
# Send hostname for visibility in router, but use MAC for client ID
SendHostname=true
# IAID must be set to ensure consistent identification
IAID=0
EOFBR0

# Create service to fix bridge MAC address
cat > /etc/systemd/system/media-bridge-fix-mac.service << 'EOFMACFIX'
[Unit]
Description=Fix bridge MAC address for DHCP persistence
After=systemd-networkd.service
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/media-bridge-fix-mac
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFMACFIX

# Enable services (use different methods based on what's available)
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable systemd-networkd 2>/dev/null || true
    systemctl enable systemd-resolved 2>/dev/null || true
    # Enable Avahi for NDI discovery
    systemctl enable avahi-daemon 2>/dev/null || true
    # Enable MAC fix service
    systemctl enable media-bridge-fix-mac 2>/dev/null || true
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

    # Bridge will automatically inherit MAC from first enslaved interface
    # This ensures DHCP client ID consistency across reboots
    
    # Create directory for systemd-networkd to persist DHCP leases
    # This is the standard location where systemd-networkd expects to save leases
    # Without this directory, leases are lost on reboot causing IP changes
    mkdir -p "$ROOTFS_DIR/var/lib/systemd/network"
    chown systemd-network:systemd-network "$ROOTFS_DIR/var/lib/systemd/network"
    
    # Create systemd-networkd override to ensure lease persistence
    # Ubuntu 24.04 defaults to /run which is tmpfs and cleared on reboot
    # We need to explicitly configure StateDirectory for persistence
    mkdir -p "$ROOTFS_DIR/etc/systemd/system/systemd-networkd.service.d"
    cat > "$ROOTFS_DIR/etc/systemd/system/systemd-networkd.service.d/lease-persistence.conf" << 'EOFLEASE'
[Service]
# Ensure DHCP leases are stored in persistent location
# Without this, leases are stored in /run and lost on reboot
StateDirectory=systemd/network
StateDirectoryMode=0755
# Also copy leases on shutdown to persistent location
ExecStopPost=/bin/sh -c 'cp -p /run/systemd/netif/leases/* /var/lib/systemd/network/ 2>/dev/null || true'
# And restore on startup
ExecStartPre=/bin/sh -c 'mkdir -p /run/systemd/netif/leases && cp -p /var/lib/systemd/network/* /run/systemd/netif/leases/ 2>/dev/null || true'
EOFLEASE
}

export -f configure_network
