#!/bin/bash
# Dante audio bridge configuration using Inferno implementation
# This module adds Dante audio networking support

configure_dante_audio() {
    log "Configuring Dante audio bridge with Inferno..."
    
    # Create Dante configuration directory
    mkdir -p /mnt/usb/etc/ndi-bridge
    mkdir -p /mnt/usb/opt/inferno
    mkdir -p /mnt/usb/opt/statime
    
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
EOFDANTE
    
    # Check if pre-compiled binaries exist
    DANTE_PKG_DIR="$(dirname "$0")/../build/dante-package"
    
    if [ -f "$DANTE_PKG_DIR/lib/libasound_module_pcm_inferno.so" ] && \
       [ -f "$DANTE_PKG_DIR/bin/statime" ]; then
        log "Using pre-compiled Dante binaries..."
        
        # Copy pre-compiled binaries
        mkdir -p /mnt/usb/usr/lib/x86_64-linux-gnu/alsa-lib
        cp "$DANTE_PKG_DIR/lib/libasound_module_pcm_inferno.so" \
           /mnt/usb/usr/lib/x86_64-linux-gnu/alsa-lib/
        
        mkdir -p /mnt/usb/usr/local/bin
        [ -f "$DANTE_PKG_DIR/bin/inferno2pipe" ] && \
            cp "$DANTE_PKG_DIR/bin/inferno2pipe" /mnt/usb/usr/local/bin/
        
        cp "$DANTE_PKG_DIR/bin/statime" /mnt/usb/usr/local/bin/
        
        # Copy Statime config
        if [ -f "$DANTE_PKG_DIR/config/statime.conf" ]; then
            cp "$DANTE_PKG_DIR/config/statime.conf" /mnt/usb/etc/statime.conf
        fi
        
        log "Pre-compiled Dante binaries installed"
        
        # Still need to create services and configs in chroot
        cat >> /mnt/usb/tmp/configure-system.sh << 'EOFDANTECFG'
echo "Configuring Dante audio services..."
EOFDANTECFG
        
    else
        log "Pre-compiled binaries not found, will compile in chroot..."
        
        # Add full compilation to chroot script
        cat >> /mnt/usb/tmp/configure-system.sh << 'EOFDANTECFG'

# Install Dante audio bridge with compilation
echo "Installing Dante audio bridge..."

# Install Rust from Ubuntu repositories (faster than rustup)
echo "Installing Rust from Ubuntu repos..."
apt-get update -qq
apt-get install -y -qq rustc-1.82 cargo-1.82 pkg-config libasound2-dev build-essential git 2>&1 | tail -10

# Create symlinks for cargo and rustc
update-alternatives --install /usr/bin/cargo cargo /usr/bin/cargo-1.82 100
update-alternatives --install /usr/bin/rustc rustc /usr/bin/rustc-1.82 100

# Verify Rust installation
rustc --version

# Clone and build Inferno
echo "Building Inferno Dante implementation (this will take 5-10 minutes)..."
cd /opt
git clone --recurse-submodules https://github.com/teodly/inferno.git 2>&1 | head -5
cd inferno

# Remove lock file to avoid version conflicts
rm -f Cargo.lock

# Build Inferno
cargo build --release 2>&1 | tail -10

# Install the ALSA plugin
if [ -f target/release/libasound_module_pcm_inferno.so ]; then
    mkdir -p /usr/lib/x86_64-linux-gnu/alsa-lib
    cp target/release/libasound_module_pcm_inferno.so /usr/lib/x86_64-linux-gnu/alsa-lib/
    echo "Inferno ALSA plugin installed"
else
    echo "Warning: Inferno ALSA plugin not found"
fi

# Install inferno2pipe utility if built
if [ -f target/release/inferno2pipe ]; then
    cp target/release/inferno2pipe /usr/local/bin/
fi

# Clone and build Statime (PTP daemon for Inferno)
echo "Building Statime PTP daemon..."
cd /opt
git clone --recurse-submodules -b inferno-dev https://github.com/teodly/statime.git 2>&1 | head -5
cd statime
cargo build --release 2>&1 | tail -10

# Install Statime
if [ -f target/release/statime ]; then
    cp target/release/statime /usr/local/bin/
    echo "Statime installed"
fi

# Copy Statime configuration
if [ -f inferno-ptpv1.toml ]; then
    cp inferno-ptpv1.toml /etc/statime.conf
    sed -i 's/interface = ".*"/interface = "br0"/' /etc/statime.conf
fi

echo "Dante compilation complete"
EOFDANTECFG
    fi
    
    # Add common configuration (services, ALSA config, etc.)
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFCOMMON'

# Create ALSA configuration for Inferno
cat > /root/.asoundrc << 'EOFALSA'
# Inferno ALSA configuration
pcm.inferno {
    type inferno
    RX_CHANNELS 2
    TX_CHANNELS 2
}

pcm.dante {
    type plug
    slave.pcm inferno
}
EOFALSA

# Also create system-wide configuration
cp /root/.asoundrc /etc/asound.conf

# Create Statime systemd service
cat > /etc/systemd/system/statime.service << 'EOFSTATIME'
[Unit]
Description=Statime PTP daemon for Inferno
After=network-online.target
Wants=network-online.target
Conflicts=chronyd.service ntp.service

[Service]
Type=simple
ExecStart=/usr/local/bin/statime -c /etc/statime.conf
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSTATIME

# Create Inferno ALSA service to keep device active
cat > /etc/systemd/system/inferno-alsa.service << 'EOFINFERNO'
[Unit]
Description=Inferno Dante ALSA device
After=statime.service sound.target
Wants=statime.service

[Service]
Type=simple
Environment="INFERNO_NAME=ndi-bridge"
Environment="INFERNO_INTERFACE=br0"
Environment="HOME=/root"
ExecStart=/usr/bin/arecord -D dante -f cd -t raw -q /dev/null
Restart=always
RestartSec=5
User=root
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFINFERNO

# Create USB to Dante bridge daemon
cat > /usr/local/bin/usb-dante-bridge << 'EOFBRIDGE'
#!/bin/bash
# Bridge USB audio to/from Dante network

export INFERNO_NAME=${HOSTNAME:-ndi-bridge}
export INFERNO_INTERFACE=br0

# Find first USB audio device (skip HDMI)
USB_CARD=$(aplay -l 2>/dev/null | grep -E "USB Audio|Arturia|Behringer|Focusrite|Scarlett" | head -1 | sed 's/card \([0-9]\).*/\1/')

if [ -z "$USB_CARD" ]; then
    echo "No USB audio device found"
    exit 1
fi

echo "Bridging USB audio card $USB_CARD to Dante network"

# Start bidirectional bridge
arecord -D plughw:${USB_CARD},0 -f cd -t raw 2>/dev/null | aplay -D dante -f cd -t raw 2>/dev/null &
CAPTURE_PID=$!

arecord -D dante -f cd -t raw 2>/dev/null | aplay -D plughw:${USB_CARD},0 -f cd -t raw 2>/dev/null &
PLAYBACK_PID=$!

echo "Bridge active (Capture PID: $CAPTURE_PID, Playback PID: $PLAYBACK_PID)"
wait $CAPTURE_PID $PLAYBACK_PID
EOFBRIDGE
chmod +x /usr/local/bin/usb-dante-bridge

# Create service for USB-Dante bridge
cat > /etc/systemd/system/usb-dante-bridge.service << 'EOFUSBBRIDGE'
[Unit]
Description=USB to Dante Audio Bridge
After=inferno-alsa.service sound.target
Wants=inferno-alsa.service

[Service]
Type=simple
ExecStart=/usr/local/bin/usb-dante-bridge
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOFUSBBRIDGE

# Enable services
systemctl enable statime.service 2>/dev/null || true
systemctl enable inferno-alsa.service 2>/dev/null || true
# USB bridge is optional - only enable if USB audio device is present
systemctl enable usb-dante-bridge.service 2>/dev/null || true

echo "Dante audio bridge configuration complete"
EOFCOMMON
}

export -f configure_dante_audio