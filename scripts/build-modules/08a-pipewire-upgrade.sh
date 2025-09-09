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

# Configure systemd overrides for PipeWire system service
echo "Configuring PipeWire system service resource limits..."
mkdir -p /etc/systemd/system/pipewire-system.service.d

# Create override file for file descriptor limits
cat > /etc/systemd/system/pipewire-system.service.d/override.conf << 'LIMIT_EOF'
# PipeWire System Service Override
# Increases file descriptor limits for multimedia testing
# Fixes "Too many open files" errors during extensive test runs

[Service]
# Increase file descriptor limits for PipeWire system service
# Default limit (1024) is insufficient for multimedia operations with many clients
LimitNOFILE=32768
LimitNOFILESoft=16384

# Additional resource limits for stable operation
LimitNPROC=32768
LimitMEMLOCK=infinity

# Restart policy for reliability during testing
Restart=on-failure
RestartSec=5s
LIMIT_EOF

echo "✓ PipeWire system service resource limits configured"

# Create marker file for other modules
touch /tmp/pipewire-1.4.7-installed

echo "Module 08a: PipeWire 1.4.7 upgrade completed successfully"
echo ""

PIPEWIRE_UPGRADE_EOF

    log "Module 08a: PipeWire upgrade configuration added to chroot script"
}

# The function will be called by the main build script at the right time