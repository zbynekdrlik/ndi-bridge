#!/bin/bash
# Base system setup - hostname, users, basic configuration

setup_base_system() {
    log "Setting up base system configuration..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFBASE'

# Set hostname
echo "media-bridge" > /etc/hostname
cat > /etc/hosts << EOFHOSTS
127.0.0.1 localhost
127.0.1.1 media-bridge
EOFHOSTS

# Set root password
echo "root:${ROOT_PASSWORD}" | chpasswd

# Disable power button shutdown
mkdir -p /etc/systemd/logind.conf.d/
cat > /etc/systemd/logind.conf.d/00-disable-power-key.conf << 'EOFPOWERKEY'
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleRebootKey=ignore
HandleRebootKeyLongPress=ignore
EOFPOWERKEY

# Configure SSH
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    # Add SSH cipher/MAC configuration to prevent corruption issues
    echo "" >> /etc/ssh/sshd_config
    echo "# Media Bridge SSH configuration" >> /etc/ssh/sshd_config
    echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
    echo "MACs umac-128-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com" >> /etc/ssh/sshd_config
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable ssh
    else
        update-rc.d ssh enable 2>/dev/null || true
    fi
fi

# Disable unnecessary grub update services
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable grub-common.service 2>/dev/null || true
    systemctl disable grub-initrd-fallback.service 2>/dev/null || true
    systemctl mask grub-common.service 2>/dev/null || true
    systemctl mask grub-initrd-fallback.service 2>/dev/null || true
fi

# Install and configure systemd-resolved for proper DHCP DNS handling
apt-get update -qq
apt-get install -y -qq --no-install-recommends systemd-resolved

# Enable systemd-resolved
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable systemd-resolved 2>/dev/null || true
fi

# Configure systemd-resolved to work with systemd-networkd
mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/media-bridge.conf << 'EOFRESOLVEDCONF'
[Resolve]
# Use DNS from DHCP (systemd-networkd) with fallback servers
FallbackDNS=8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1
# Disable unnecessary features for appliance
DNSSEC=no
DNSOverTLS=no
# Cache DNS for performance but allow DHCP updates
Cache=yes
DNSStubListener=yes
EOFRESOLVEDCONF

# Create proper resolv.conf symlink for systemd-resolved
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Disable unnecessary services for appliance mode
if command -v systemctl >/dev/null 2>&1; then
    # Disable APT automatic updates (not needed on appliance)
    systemctl disable apt-daily.timer 2>/dev/null || true
    systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
    systemctl mask apt-daily.timer 2>/dev/null || true
    systemctl mask apt-daily-upgrade.timer 2>/dev/null || true
    systemctl mask apt-daily.service 2>/dev/null || true
    systemctl mask apt-daily-upgrade.service 2>/dev/null || true
    
    # Disable other unnecessary services for dedicated appliance
    systemctl disable motd-news.timer 2>/dev/null || true
    systemctl disable fwupd-refresh.timer 2>/dev/null || true
    systemctl disable update-notifier-download.timer 2>/dev/null || true
    systemctl disable update-notifier-motd.timer 2>/dev/null || true
    systemctl mask motd-news.timer 2>/dev/null || true
    systemctl mask fwupd-refresh.timer 2>/dev/null || true
    systemctl mask update-notifier-download.timer 2>/dev/null || true
    systemctl mask update-notifier-motd.timer 2>/dev/null || true
    
    # Disable services that aren't needed on headless appliance
    systemctl disable ModemManager 2>/dev/null || true
    systemctl disable whoopsie 2>/dev/null || true
    systemctl disable snapd 2>/dev/null || true
    systemctl mask ModemManager 2>/dev/null || true
    systemctl mask whoopsie 2>/dev/null || true
    systemctl mask snapd 2>/dev/null || true
fi

EOFBASE
}

export -f setup_base_system