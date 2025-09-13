#!/bin/bash
# Module 08a: PipeWire 1.4.7 Upgrade
# Upgrades PipeWire to version 1.4.7 using Rob Savoury's PPA for better Chrome audio isolation
# This module adds to the chroot configuration script that runs after base system installation

configure_pipewire_upgrade() {
    log "MODULE 08a: PipeWire 1.4.7 Upgrade - Configuring for chroot"
    
    # Append PipeWire upgrade to the chroot configuration script
    cat >> /mnt/usb/tmp/configure-system.sh << 'PIPEWIRE_UPGRADE_EOF'

echo ""
echo "============================"
echo "MODULE 08a: PipeWire 1.4.7 Upgrade"
echo "============================"

# Install software-properties-common for add-apt-repository
echo "Installing prerequisites for PipeWire upgrade..."
apt-get install -y -qq software-properties-common gnupg 2>&1 | head -10

# Add Rob Savoury's PPA for PipeWire 1.4.7
echo "Adding PipeWire 1.4.7 PPA..."
add-apt-repository -y ppa:savoury1/pipewire 2>&1 | head -10

# Update package lists
echo "Updating package lists..."
apt-get update -qq 2>&1 | head -10

# Install specific version of PipeWire 1.4.7
echo "Installing PipeWire 1.4.7..."
apt-get install -y -qq \
    pipewire=1.4.7-0ubuntu1~24.04.sav0 \
    pipewire-pulse=1.4.7-0ubuntu1~24.04.sav0 \
    pipewire-alsa=1.4.7-0ubuntu1~24.04.sav0 \
    libpipewire-0.3-0t64=1.4.7-0ubuntu1~24.04.sav0 \
    libpipewire-0.3-modules=1.4.7-0ubuntu1~24.04.sav0 \
    libspa-0.2-modules=1.4.7-0ubuntu1~24.04.sav0 \
    pipewire-bin=1.4.7-0ubuntu1~24.04.sav0 \
    gstreamer1.0-pipewire=1.4.7-0ubuntu1~24.04.sav0 2>&1 | head -20

# Install WirePlumber (session manager)
echo "Installing WirePlumber..."
apt-get install -y -qq wireplumber libwireplumber-0.5-0 2>&1 | head -20

# Install PulseAudio utilities for compatibility
echo "Installing PulseAudio utilities..."
apt-get install -y -qq pulseaudio-utils 2>&1 | head -20

# Verify PipeWire version
echo "Verifying PipeWire installation..."
INSTALLED_VERSION=$(pipewire --version 2>&1 | grep -oP 'pipewire \K[0-9.]+' || echo "unknown")
EXPECTED_VERSION="1.4.7"

if [[ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]]; then
    echo "WARNING: PipeWire version mismatch!"
    echo "Expected: $EXPECTED_VERSION"
    echo "Installed: $INSTALLED_VERSION"
    # Continue anyway as fallback will handle it
else
    echo "✓ PipeWire $INSTALLED_VERSION installed successfully"
fi

# Check for pw-container (available in 1.4.7)
if command -v pw-container &> /dev/null; then
    echo "✓ pw-container tool is available (for Chrome isolation)"
else
    echo "⚠ pw-container not found - Chrome isolation features may be limited"
fi

# Pin PipeWire packages to prevent accidental upgrades
echo "Pinning PipeWire packages to version 1.4.7..."
cat > /etc/apt/preferences.d/pipewire-pin << 'EOF'
Package: pipewire pipewire-* libpipewire-* libspa-*
Pin: version 1.4.7-0ubuntu1~24.04.sav0
Pin-Priority: 1001

Package: wireplumber libwireplumber-*
Pin: version 0.5.*
Pin-Priority: 900
EOF

echo "✓ PipeWire packages pinned to prevent upgrades"

# Configure PipeWire for user mode operation
echo "Configuring PipeWire for user mode with mediabridge user..."

# Create user service override directory
mkdir -p /var/lib/mediabridge/.config/systemd/user/pipewire.service.d
mkdir -p /var/lib/mediabridge/.config/systemd/user/pipewire-pulse.service.d
mkdir -p /var/lib/mediabridge/.config/systemd/user/wireplumber.service.d

# Create override for PipeWire to bind mount socket for system-wide access
cat > /var/lib/mediabridge/.config/systemd/user/pipewire.service.d/override.conf << 'PIPEWIRE_OVERRIDE_EOF'
[Service]
# Ensure /run/pipewire exists with correct permissions
ExecStartPre=/bin/sh -c 'mkdir -p /run/pipewire && chown mediabridge:audio /run/pipewire'

# Bind mount socket for system-wide access after startup
ExecStartPost=/bin/sh -c 'sleep 1; mount --bind /run/user/999/pipewire-0 /run/pipewire/pipewire-0 2>/dev/null || true'
ExecStopPost=-/bin/umount /run/pipewire/pipewire-0

# Resource limits for multimedia
LimitNOFILE=32768
LimitNPROC=32768
LimitMEMLOCK=infinity

# Restart policy for reliability
Restart=on-failure
RestartSec=5s
PIPEWIRE_OVERRIDE_EOF

# Create override for PipeWire-Pulse
cat > /var/lib/mediabridge/.config/systemd/user/pipewire-pulse.service.d/override.conf << 'PULSE_OVERRIDE_EOF'
[Service]
# Ensure /run/pipewire/pulse exists with correct permissions
ExecStartPre=/bin/sh -c 'mkdir -p /run/pipewire/pulse && chown mediabridge:audio /run/pipewire/pulse'

# Bind mount pulse socket for system-wide access
ExecStartPost=/bin/sh -c 'sleep 1; mount --bind /run/user/999/pulse /run/pipewire/pulse 2>/dev/null || true; chown -R mediabridge:audio /run/pipewire/pulse'
ExecStopPost=-/bin/umount /run/pipewire/pulse

# Resource limits
LimitNOFILE=32768
LimitNPROC=32768
PULSE_OVERRIDE_EOF

# Fix dbus.socket deadlock issue (Ubuntu desktop assumption bug)
mkdir -p /var/lib/mediabridge/.config/systemd/user/dbus.socket.d
cat > /var/lib/mediabridge/.config/systemd/user/dbus.socket.d/override.conf << 'DBUS_OVERRIDE_EOF'
[Socket]
# Remove the problematic ExecStartPost that causes deadlock
# The systemctl command needs dbus to work, but dbus isn't started yet
ExecStartPost=
DBUS_OVERRIDE_EOF

# Disable unnecessary desktop services for headless system user
# These cause timeouts during user session startup
ln -sf /dev/null /var/lib/mediabridge/.config/systemd/user/gpg-agent-ssh.socket
ln -sf /dev/null /var/lib/mediabridge/.config/systemd/user/gpg-agent.socket
ln -sf /dev/null /var/lib/mediabridge/.config/systemd/user/gpg-agent-browser.socket
ln -sf /dev/null /var/lib/mediabridge/.config/systemd/user/gpg-agent-extra.socket
ln -sf /dev/null /var/lib/mediabridge/.config/systemd/user/dirmngr.socket
ln -sf /dev/null /var/lib/mediabridge/.config/systemd/user/keyboxd.socket

# Set proper ownership
chown -R mediabridge:audio /var/lib/mediabridge/.config

# Enable user services for mediabridge
echo "Enabling PipeWire user services for mediabridge..."
# Note: This may fail in chroot, but will be retried on first boot
sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user enable pipewire.service 2>/dev/null || true
sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user enable pipewire-pulse.service 2>/dev/null || true
sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user enable wireplumber.service 2>/dev/null || true

# Create systemd drop-in to ensure user session starts on boot
mkdir -p /etc/systemd/system/user@999.service.d
cat > /etc/systemd/system/user@999.service.d/override.conf << 'USER_OVERRIDE_EOF'
[Service]
# Ensure PipeWire starts on boot for mediabridge user
Environment="XDG_RUNTIME_DIR=/run/user/999"
Environment="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus"
# Extend timeout to allow all user services to start (especially gpg-agent-ssh.socket)
TimeoutStartSec=90s

[Unit]
# No After=multi-user.target to avoid circular dependency
# The user service will start after user-runtime-dir@999.service automatically
USER_OVERRIDE_EOF

echo "✓ PipeWire configured for user mode operation"

# Configure WirePlumber for virtual device creation in user mode
echo "Configuring WirePlumber for Chrome isolation..."
mkdir -p /var/lib/mediabridge/.config/wireplumber/main.lua.d
cat > /var/lib/mediabridge/.config/wireplumber/main.lua.d/51-intercom-virtual-devices.lua << 'WIREPLUMBER_CONFIG_EOF'
-- WirePlumber configuration for Media Bridge Intercom
-- Creates virtual devices for Chrome isolation in user mode

-- Create virtual null sinks for intercom isolation
rule = {
  matches = {
    {
      { "node.name", "equals", "intercom-speaker" },
    },
  },
  apply_properties = {},
}

table.insert(alsa_monitor.rules, rule)

-- Load module to create virtual devices on startup
load_module("libpipewire-module-null-sink", {
  ["node.name"] = "intercom-speaker",
  ["node.description"] = "Intercom Speaker (Virtual)",
  ["media.class"] = "Audio/Sink",
  ["audio.position"] = "FL,FR",
  ["audio.channels"] = 2,
  ["audio.rate"] = 48000,
})

load_module("libpipewire-module-null-sink", {
  ["node.name"] = "intercom-microphone",
  ["node.description"] = "Intercom Microphone (Virtual)",
  ["media.class"] = "Audio/Sink",
  ["audio.position"] = "FL,FR",
  ["audio.channels"] = 2,
  ["audio.rate"] = 48000,
})

-- Chrome audio routing policy
-- Automatically route Chrome to virtual devices
policy_config.policy = policy_config.policy or {}
policy_config.policy["node.autoconnect"] = false
policy_config.policy["rescan.disable"] = false
policy_config.policy["move"] = {
  ["application.process.binary"] = {
    ["chrome"] = {
      ["media.role"] = "Communication",
      ["target.object"] = "intercom-speaker",
      ["target.object.source"] = "intercom-microphone.monitor",
    },
    ["google-chrome"] = {
      ["media.role"] = "Communication",
      ["target.object"] = "intercom-speaker",
      ["target.object.source"] = "intercom-microphone.monitor",
    },
  },
}
WIREPLUMBER_CONFIG_EOF

chown -R mediabridge:audio /var/lib/mediabridge/.config

echo "✓ WirePlumber configured for Chrome isolation"

# Create marker file for other modules
touch /tmp/pipewire-1.4.7-installed

echo "Module 08a: PipeWire 1.4.7 upgrade completed successfully"
echo ""

PIPEWIRE_UPGRADE_EOF

    log "Module 08a: PipeWire upgrade configuration added to chroot script"
}

# The function will be called by the main build script at the right time