#!/bin/bash
# Dante audio bridge configuration using Inferno implementation
# Clean, production-ready implementation focused on Dante→USB playback

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

# Number of audio channels (2 = stereo)
DANTE_CHANNELS=2

# Sample rate - MUST BE 96000 for professional Dante networks
DANTE_SAMPLE_RATE=96000

# Device name for Dante network
DANTE_DEVICE_NAME=ndi-bridge

# Enable auto-start
DANTE_ENABLED=true
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
        cp "$DANTE_PKG_DIR/bin/statime" /mnt/usb/usr/local/bin/
        
        # Copy Statime config if available
        if [ -f "$DANTE_PKG_DIR/config/statime.conf" ]; then
            cp "$DANTE_PKG_DIR/config/statime.conf" /mnt/usb/etc/statime.conf
        fi
        
        log "Pre-compiled Dante binaries installed"
        
    else
        log "Pre-compiled binaries not found, will compile in chroot..."
        
        # Add compilation to chroot script
        cat >> /mnt/usb/tmp/configure-system.sh << 'EOFDANTECOMPILE'

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

# Clone and build Statime (MODIFIED FORK with PTPv1 support for Dante)
# CRITICAL: We MUST use teodly's fork with inferno-dev branch
# Upstream Statime only supports PTPv2, which is incompatible with Dante PTPv1
echo "Building Statime PTP daemon (Inferno fork with PTPv1 support)..."
cd /opt
git clone --recurse-submodules -b inferno-dev https://github.com/teodly/statime.git 2>&1 | head -5
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clone Statime fork with PTPv1 support!"
    echo "Cannot proceed without PTPv1 support for Dante"
    exit 1
fi
cd statime
cargo build --release 2>&1 | tail -10

# Install Statime
if [ -f target/release/statime ]; then
    cp target/release/statime /usr/local/bin/
    echo "Statime installed"
fi

# Copy Statime configuration - FOLLOWER MODE
# CRITICAL: ndi-bridge must be PTP follower, not master
if [ -f /tmp/helper-scripts/statime-follower.conf ]; then
    cp /tmp/helper-scripts/statime-follower.conf /etc/statime.conf
elif [ -f inferno-ptpv1.toml ]; then
    cp inferno-ptpv1.toml /etc/statime.conf
    # Modify to ensure we're never PTP master
    cat >> /etc/statime.conf << 'EOFOLLOWER'

# OVERRIDE: Ensure ndi-bridge is always PTP follower
[ptp]
priority1 = 255
priority2 = 255
clock_class = 255
EOFOLLOWER
fi

echo "Dante compilation complete"
EOFDANTECOMPILE
    fi
    
    # Add common configuration (services, ALSA config)
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFDANTECONFIG'

# Configure Dante audio services
echo "Configuring Dante audio services..."

# Create ALSA configuration for Inferno
# CRITICAL: Must use 'type inferno' directly, NOT 'type plug'!
cat > /root/.asoundrc << 'EOFALSA'
# Inferno Dante PCM device at 96kHz
# IMPORTANT: Must use 'type inferno' directly for discovery ports to open
pcm.dante {
    type inferno
    RX_CHANNELS 2
    TX_CHANNELS 2
    SAMPLE_RATE 96000
}
EOFALSA

# Also create system-wide configuration
cp /root/.asoundrc /etc/asound.conf

# Copy service files from helper-scripts
cp /tmp/helper-scripts/statime.service /etc/systemd/system/
cp /tmp/helper-scripts/dante-bridge.service /etc/systemd/system/

# Copy the main bridge scripts
cp /tmp/helper-scripts/dante-bridge-production /usr/local/bin/
chmod +x /usr/local/bin/dante-bridge-production

# Legacy script for fallback
if [ -f /tmp/helper-scripts/dante-bridge ]; then
    cp /tmp/helper-scripts/dante-bridge /usr/local/bin/
    chmod +x /usr/local/bin/dante-bridge
fi

# Copy PipeWire configuration for Dante
mkdir -p /etc/pipewire/pipewire.conf.d
cp /tmp/helper-scripts/pipewire-dante.conf /etc/pipewire/pipewire.conf.d/90-dante-bridge.conf

# Ensure PipeWire is installed and configured
if ! command -v pipewire >/dev/null 2>&1; then
    echo "Installing PipeWire for clock drift compensation..."
    apt-get update -qq
    apt-get install -y -qq pipewire pipewire-alsa pipewire-audio wireplumber 2>&1 | tail -5
fi

# Ensure PipeWire services are enabled
systemctl enable pipewire.service 2>/dev/null || true
systemctl enable wireplumber.service 2>/dev/null || true

# Copy helper scripts for status and configuration
for script in ndi-bridge-dante-status ndi-bridge-dante-config ndi-bridge-dante-logs; do
    if [ -f /tmp/helper-scripts/$script ]; then
        cp /tmp/helper-scripts/$script /usr/local/bin/
        chmod +x /usr/local/bin/$script
    fi
done

# Enable services
systemctl enable statime.service 2>/dev/null || true
systemctl enable dante-bridge.service 2>/dev/null || true

# Disable conflicting time sync services when Dante is enabled
systemctl disable ptp4l.service 2>/dev/null || true
systemctl disable phc2sys.service 2>/dev/null || true

echo "Dante audio bridge configuration complete"
echo "Device will be visible as '${HOSTNAME:-ndi-bridge}' in Dante Controller"
echo "Audio routing: Dante network ↔ USB audio interface (Arturia/Focusrite/etc)"
EOFDANTECONFIG
}

export -f configure_dante_audio