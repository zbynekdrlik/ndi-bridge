#!/bin/bash
# Module 10a: PipeWire User Session Configuration
# Configures PipeWire to run properly as a user session service with loginctl lingering
# This is the standard and recommended way to run PipeWire on headless/embedded systems

configure_pipewire_user_session() {
    log "MODULE 10a: PipeWire User Session Configuration"
    
    # This runs in the chroot environment
    cat >> /mnt/usb/tmp/configure-system.sh << 'PIPEWIRE_USER_EOF'

echo ""
echo "============================"
echo "MODULE 10a: PipeWire User Session Configuration"
echo "============================"

# Enable lingering for mediabridge user so services start at boot
echo "Enabling user lingering for mediabridge..."
loginctl enable-linger mediabridge || echo "Note: loginctl may not work in chroot, will be enabled on first boot"

# Create systemd user directory for mediabridge
echo "Creating systemd user directories..."
mkdir -p /var/lib/mediabridge/.config/systemd/user
chown -R mediabridge:mediabridge /var/lib/mediabridge/.config

# Disable any system-wide PipeWire services if they exist
echo "Disabling system-wide PipeWire services..."
systemctl disable pipewire-system 2>/dev/null || true
systemctl disable pipewire-pulse-system 2>/dev/null || true
systemctl disable wireplumber-system 2>/dev/null || true

# Enable user session PipeWire services for mediabridge
echo "Configuring user session services..."
sudo -u mediabridge mkdir -p /var/lib/mediabridge/.config/systemd/user/default.target.wants
sudo -u mediabridge ln -sf /usr/lib/systemd/user/pipewire.service /var/lib/mediabridge/.config/systemd/user/default.target.wants/ 2>/dev/null || true
sudo -u mediabridge ln -sf /usr/lib/systemd/user/pipewire-pulse.service /var/lib/mediabridge/.config/systemd/user/default.target.wants/ 2>/dev/null || true
sudo -u mediabridge ln -sf /usr/lib/systemd/user/wireplumber.service /var/lib/mediabridge/.config/systemd/user/default.target.wants/ 2>/dev/null || true

# Create a first-boot script to enable lingering (since loginctl doesn't work in chroot)
cat > /etc/systemd/system/enable-mediabridge-linger.service << 'EOF'
[Unit]
Description=Enable lingering for mediabridge user
After=multi-user.target
ConditionPathExists=!/var/lib/mediabridge/.linger-enabled

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'loginctl enable-linger mediabridge && touch /var/lib/mediabridge/.linger-enabled'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable enable-mediabridge-linger.service

# Configure ALSA to use PipeWire
echo "Configuring ALSA to use PipeWire..."
if [ -f /usr/share/doc/pipewire/examples/alsa.conf.d/99-pipewire-default.conf ]; then
    cp /usr/share/doc/pipewire/examples/alsa.conf.d/99-pipewire-default.conf /etc/alsa/conf.d/ 2>/dev/null || true
fi

# Create PipeWire user configuration directory
echo "Creating PipeWire configuration directory..."
sudo -u mediabridge mkdir -p /var/lib/mediabridge/.config/pipewire
sudo -u mediabridge mkdir -p /var/lib/mediabridge/.config/wireplumber

# Set up environment for mediabridge user
echo "Setting up user environment..."
cat >> /var/lib/mediabridge/.bashrc << 'BASHRC'

# PipeWire environment
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export PIPEWIRE_RUNTIME_DIR=$XDG_RUNTIME_DIR
export PULSE_RUNTIME_PATH=$XDG_RUNTIME_DIR/pulse

BASHRC

# Create a systemd tmpfiles configuration for runtime directory
echo "Creating runtime directory configuration..."
cat > /etc/tmpfiles.d/mediabridge-runtime.conf << 'TMPFILES'
# Runtime directory for mediabridge user
d /run/user/999 0700 mediabridge mediabridge -
TMPFILES

# Ensure mediabridge is in required groups
echo "Adding mediabridge to audio groups..."
usermod -a -G audio,video,pipewire mediabridge 2>/dev/null || true

# Remove old system-wide configuration files if they exist
echo "Cleaning up old system-wide configurations..."
rm -f /etc/systemd/system/pipewire-system.service
rm -f /etc/systemd/system/pipewire-pulse-system.service
rm -f /etc/systemd/system/wireplumber-system.service
rm -f /etc/pipewire/pipewire-system.conf

# Create a helper script to check PipeWire status
echo "Creating PipeWire status helper..."
cat > /usr/local/bin/pipewire-status << 'SCRIPT'
#!/bin/bash
echo "=== PipeWire User Session Status ==="
echo "User: mediabridge (UID 999)"
echo ""
echo "Linger status:"
loginctl show-user mediabridge | grep Linger
echo ""
echo "User services:"
systemctl --user -M mediabridge@ status pipewire pipewire-pulse wireplumber --no-pager
echo ""
echo "Sockets:"
ls -la /run/user/999/pipewire* /run/user/999/pulse* 2>/dev/null || echo "No sockets found yet"
echo ""
echo "To interact with PipeWire as root, use:"
echo "  sudo -u mediabridge pactl info"
echo "  sudo -u mediabridge pw-cli ls"
SCRIPT
chmod +x /usr/local/bin/pipewire-status

echo "✓ PipeWire configured for user session with lingering"
echo "✓ Services will start automatically on boot for mediabridge user"
echo ""

PIPEWIRE_USER_EOF

    log "Module 10a: PipeWire user session configuration completed"
}

# The function will be called by the main build script