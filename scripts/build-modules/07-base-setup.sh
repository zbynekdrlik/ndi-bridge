#!/bin/bash
# Base system setup - hostname, users, basic configuration

setup_base_system() {
    log "Setting up base system configuration..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFBASE'

# Set hostname
echo "ndi-bridge" > /etc/hostname
cat > /etc/hosts << EOFHOSTS
127.0.0.1 localhost
127.0.1.1 ndi-bridge
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
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable ssh
    else
        update-rc.d ssh enable 2>/dev/null || true
    fi
fi

EOFBASE
}

export -f setup_base_system