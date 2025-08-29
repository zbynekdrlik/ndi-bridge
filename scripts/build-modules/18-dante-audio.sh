#!/bin/bash
# Dante audio bridge configuration using Inferno implementation
# This module adds Dante audio networking support

configure_dante_audio() {
    log "Configuring Dante audio bridge..."
    
    # Create Dante configuration directory
    mkdir -p /mnt/usb/etc/ndi-bridge
    
    # Create default Dante configuration
    cat > /mnt/usb/etc/ndi-bridge/dante.conf << 'EOFDANTE'
# Dante Audio Bridge Configuration
# Using Inferno open-source implementation

# Network interface (uses bridge by default)
DANTE_INTERFACE=br0

# Number of audio channels (2 = stereo, up to 64 supported)
DANTE_CHANNELS=2

# Sample rate (48000 or 44100)
DANTE_SAMPLE_RATE=48000

# Device name for Dante network
DANTE_DEVICE_NAME=ndi-bridge

# Enable auto-start
DANTE_ENABLED=true

# Audio routing mode (usb2dante, dante2usb, bidirectional)
DANTE_MODE=bidirectional

# PTP clock device (auto-detected if not specified)
DANTE_PTP_DEVICE=/dev/ptp0
EOFDANTE
    
    # Add Dante setup to chroot configuration script
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFDANTECFG'

# Install Dante audio bridge dependencies
echo "Installing Dante audio bridge dependencies..."

# Install Rust toolchain for building Inferno
apt-get update -qq
apt-get install -y -qq curl build-essential pkg-config libasound2-dev git cargo 2>&1 | head -20

# Create directory for Inferno
mkdir -p /opt/inferno

# Clone and build Inferno (unofficial Dante implementation)
echo "Building Inferno Dante implementation..."
cd /opt
git clone --depth 1 https://github.com/teodly/inferno.git 2>&1 | head -10
cd inferno

# Build with cargo (this may take a while)
echo "Compiling Inferno (this will take 5-10 minutes)..."
export CARGO_HOME=/opt/cargo
export RUSTUP_HOME=/opt/rustup
cargo build --release 2>&1 | tail -20

# Install the ALSA plugin
if [ -f target/release/libalsa_pcm_inferno.so ]; then
    mkdir -p /usr/lib/x86_64-linux-gnu/alsa-lib
    cp target/release/libalsa_pcm_inferno.so /usr/lib/x86_64-linux-gnu/alsa-lib/
    echo "Inferno ALSA plugin installed"
else
    echo "Warning: Inferno build may have failed"
fi

# Create ALSA configuration for Inferno
cat > /etc/asound.conf << 'EOFALSA'
# ALSA configuration for Dante/Inferno audio bridge

pcm.dante_out {
    type inferno
    channels 2
    mode playback
}

pcm.dante_in {
    type inferno
    channels 2
    mode capture
}

# Create a duplex device for bidirectional audio
pcm.dante {
    type asym
    playback.pcm "dante_out"
    capture.pcm "dante_in"
}

# Make Dante available as default if needed
# pcm.!default {
#     type plug
#     slave.pcm "dante"
# }
EOFALSA

# Create systemd service for Dante bridge
cat > /etc/systemd/system/dante-bridge.service << 'EOFSERVICE'
[Unit]
Description=Dante Audio Bridge (Inferno)
After=network-online.target ptp4l.service
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/ndi-bridge/dante.conf
Environment="INFERNO_BIND_INTERFACE=br0"
Environment="INFERNO_CHANNELS=2"
Environment="CLOCK_PATH=/dev/ptp0"
ExecStartPre=/bin/sleep 5
ExecStart=/opt/inferno/target/release/inferno
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Enable the service
systemctl enable dante-bridge.service 2>/dev/null || true

echo "Dante audio bridge configuration complete"
EOFDANTECFG
}

export -f configure_dante_audio