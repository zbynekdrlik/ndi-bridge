#!/bin/bash
# System configuration module - contains the main configuration logic

configure_system() {
    log "Creating system configuration script..."
    
    # Create the main configuration script that will run in chroot
    cat > /mnt/usb/tmp/configure-system.sh << 'EOFSCRIPT'
#!/bin/bash
set -e

# Prevent interactive prompts
export DEBIAN_FRONTEND=noninteractive

echo "Installing essential packages..."
apt-get update
apt-get install -y -qq --no-install-recommends \
    linux-image-generic \
    linux-headers-generic \
    grub-efi-amd64 \
    grub-efi-amd64-signed \
    shim-signed \
    systemd \
    systemd-sysv \
    udev \
    iproute2 \
    net-tools \
    bridge-utils \
    openssh-server \
    sudo \
    nano \
    wget \
    ca-certificates \
    iputils-ping \
    zstd 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || true

# Try to install DHCP client (different package names in different Ubuntu versions)
apt-get install -y -qq --no-install-recommends isc-dhcp-client 2>/dev/null || \
apt-get install -y -qq --no-install-recommends dhcpcd5 2>/dev/null || \
echo "Note: Using systemd-networkd for DHCP (default in Ubuntu 24.04)"

# Install optional packages (don't fail if unavailable)
echo "Installing optional packages..."
apt-get install -y -qq --no-install-recommends \
    avahi-daemon \
    avahi-utils \
    libavahi-common3 \
    libavahi-client3 \
    libnss-mdns \
    htop 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || true

# Try to install v4l2 tools with different package names
apt-get install -y -qq --no-install-recommends v4l-utils 2>/dev/null || \
apt-get install -y -qq --no-install-recommends v4l2-tools 2>/dev/null || \
apt-get install -y -qq --no-install-recommends v4l2loopback-utils 2>/dev/null || true

# Network monitoring tools
echo "Installing network monitoring tools..."
apt-get install -y -qq --no-install-recommends nload iftop bmon 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || true

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
EOFSCRIPT

    chmod +x /mnt/usb/tmp/configure-system.sh
}

export -f configure_system