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

echo "Configuring APT repositories..."
# Enable universe repository for additional packages
cat > /etc/apt/sources.list << EOFAPT
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe multiverse
EOFAPT

echo "Installing essential packages..."
apt-get update -qq
# Fix any held packages before installing
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y -qq 2>/dev/null || true
# Install systemd first to ensure it's available
apt-get install -y -qq --no-install-recommends systemd systemd-sysv 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || true
# Install kernel and boot-related packages first
echo "Installing kernel and bootloader packages..."
apt-get install -y -qq --no-install-recommends \
    linux-image-generic \
    linux-headers-generic \
    initramfs-tools \
    initramfs-tools-core 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || true

# Install GRUB packages (UEFI only, same as obsolete script)
echo "Installing GRUB packages..."
apt-get install -y -qq --no-install-recommends \
    grub-efi-amd64 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || true

# Install remaining system packages
echo "Installing system packages..."
apt-get install -y -qq --no-install-recommends \
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
# Update package list again to ensure universe packages are available
apt-get update -qq
# Install each tool separately to identify which ones fail
for tool in nload iftop bmon; do
    echo "  Installing $tool..."
    apt-get install -y -qq --no-install-recommends $tool 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || echo "  Warning: $tool not available"
done

# Disable WiFi completely (NDI Bridge needs Ethernet only)
echo "Disabling WiFi and wireless modules..."
# Blacklist iwlwifi and related modules to prevent boot hangs
cat > /etc/modprobe.d/blacklist-wifi.conf << EOFWIFI
# Disable all WiFi modules for NDI Bridge appliance
# This prevents boot hangs with iwlwifi on Intel systems
blacklist iwlwifi
blacklist iwldvm
blacklist iwlmvm
blacklist mac80211
blacklist cfg80211
blacklist rfkill
blacklist bluetooth
blacklist btusb
blacklist ath9k
blacklist ath9k_common
blacklist ath9k_hw
blacklist ath
blacklist wl
blacklist b43
blacklist b43legacy
blacklist ssb
blacklist bcm43xx
blacklist brcm80211
blacklist brcmfmac
blacklist brcmsmac
blacklist tg3
EOFWIFI

# Also disable WiFi services
systemctl disable wpa_supplicant 2>/dev/null || true
systemctl disable NetworkManager 2>/dev/null || true

# Remove WiFi packages if they were installed
apt-get remove -y -qq wpasupplicant wireless-tools network-manager 2>/dev/null || true

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
EOFSCRIPT

    chmod +x /mnt/usb/tmp/configure-system.sh
}

export -f configure_system