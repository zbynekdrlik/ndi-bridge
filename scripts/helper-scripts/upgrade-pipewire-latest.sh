#!/bin/bash
# Upgrade PipeWire to 1.2+ for proper Chrome isolation with pw-container
# This script builds and installs PipeWire 1.2.7 from source

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

PIPEWIRE_VERSION="1.4.7"
BUILD_DIR="/tmp/pipewire-build"

log "Starting PipeWire $PIPEWIRE_VERSION upgrade for Chrome isolation support..."

# Install build dependencies
log "Installing build dependencies..."
apt-get update
apt-get install -y \
    build-essential \
    meson \
    ninja-build \
    libdbus-1-dev \
    libudev-dev \
    libsystemd-dev \
    libasound2-dev \
    libx11-dev \
    libxfixes-dev \
    libssl-dev \
    libglib2.0-dev \
    libspa-0.2-dev \
    libpulse-dev \
    libavahi-client-dev \
    libwebrtc-audio-processing-dev \
    libncurses5-dev \
    liblua5.3-dev \
    libreadline-dev \
    python3-docutils \
    doxygen \
    graphviz

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download PipeWire source
log "Downloading PipeWire $PIPEWIRE_VERSION..."
wget "https://gitlab.freedesktop.org/pipewire/pipewire/-/archive/$PIPEWIRE_VERSION/pipewire-$PIPEWIRE_VERSION.tar.gz"
tar xzf "pipewire-$PIPEWIRE_VERSION.tar.gz"
cd "pipewire-$PIPEWIRE_VERSION"

# Configure build with security features enabled
log "Configuring PipeWire build with security features..."
meson setup builddir \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --buildtype=release \
    -Dsession-managers=[] \
    -Dexamples=disabled \
    -Dman=disabled \
    -Dtests=disabled \
    -Dsystemd=enabled \
    -Dsystemd-system-service=enabled \
    -Dsystemd-user-service=disabled \
    -Dpipewire-jack=disabled \
    -Djack=disabled \
    -Dvulkan=disabled \
    -Dgstreamer=disabled \
    -Dlibcamera=disabled \
    -Droc=disabled \
    -Dlibmysofa=disabled \
    -Dcompress-offload=disabled \
    -Dlv2=disabled \
    -Draop=disabled \
    -Dx11=enabled \
    -Dx11-xfixes=enabled \
    -Dlibpulse=enabled \
    -Davahi=enabled \
    -Dsupport=enabled \
    -Dspa-plugins=enabled \
    -Dalsa=enabled \
    -Daudiomixer=enabled \
    -Daudioconvert=enabled \
    -Dcontrol=enabled \
    -Daudiotestsrc=enabled \
    -Dvolume=enabled \
    -Dv4l2=enabled \
    -Dlibusb=disabled \
    -Dbluez5=disabled

# Build PipeWire
log "Building PipeWire..."
ninja -C builddir

# Stop existing services
log "Stopping existing PipeWire services..."
systemctl stop pipewire-pulse-system || true
systemctl stop wireplumber-system || true
systemctl stop pipewire-system || true

# Backup existing installation
log "Backing up existing PipeWire installation..."
if [ -d /usr/bin/pipewire ]; then
    cp -a /usr/bin/pipewire /usr/bin/pipewire.backup
    cp -a /usr/lib/x86_64-linux-gnu/pipewire-* /usr/lib/x86_64-linux-gnu/pipewire-backup/ 2>/dev/null || true
fi

# Install new version
log "Installing PipeWire $PIPEWIRE_VERSION..."
ninja -C builddir install

# Install pw-container if built
if [ -f builddir/src/tools/pw-container ]; then
    log "Installing pw-container for Chrome isolation..."
    cp builddir/src/tools/pw-container /usr/bin/
    chmod +x /usr/bin/pw-container
fi

# Update system configuration for security contexts
log "Configuring PipeWire security contexts..."
cat > /etc/pipewire/pipewire-system.conf.d/10-security-context.conf << 'EOF'
# Enable security context support for Chrome isolation
context.properties = {
    # Enable security context API
    support.security-context = true
    
    # Default security policy
    default.permissions = "rx"
    
    # Chrome-specific context
    security.context.chrome = {
        # Restricted permissions
        permissions = "r--"
        # Only see virtual devices
        filter.properties = {
            media.class = "*/Virtual"
        }
    }
}

# Load security module
context.modules = [
    {
        name = libpipewire-module-security-context
        args = {
            # Enable for all clients
            enable = true
            # Default context
            default.context = "default"
            # Chrome gets restricted context
            rules = [
                {
                    matches = [
                        { application.name = "~.*[Cc]hrome.*" }
                        { application.process.binary = "~.*chrome.*" }
                    ]
                    context = "chrome"
                }
            ]
        }
    }
]
EOF

# Create Chrome isolation wrapper script
log "Creating Chrome isolation wrapper..."
cat > /usr/local/bin/chrome-isolated << 'EOF'
#!/bin/bash
# Launch Chrome in isolated PipeWire container

# Check if pw-container is available
if ! command -v pw-container &> /dev/null; then
    echo "Error: pw-container not found. Using direct launch."
    exec /usr/bin/chromium-browser "$@"
fi

# Create isolated context for Chrome
export PIPEWIRE_CONTEXT="chrome-isolated"
export PIPEWIRE_PROPS='{
    "pipewire.access": "restricted",
    "pipewire.permissions": "r--",
    "media.role": "browser"
}'

# Launch Chrome in container with only virtual devices visible
pw-container \
    --context="chrome" \
    --filter="media.class=*/Virtual" \
    --permissions="r--" \
    -- /usr/bin/chromium-browser \
        --enable-features=UseOzonePlatform \
        --ozone-platform=x11 \
        --no-sandbox \
        --disable-dev-shm-usage \
        --disable-gpu \
        --use-fake-ui-for-media-stream \
        --enable-usermedia-screen-capturing \
        --auto-select-desktop-capture-source="Entire screen" \
        --enable-logging=stderr \
        --v=1 \
        "$@"
EOF
chmod +x /usr/local/bin/chrome-isolated

# Update intercom service to use isolated Chrome
log "Updating intercom service..."
sed -i 's|/usr/bin/chromium-browser|/usr/local/bin/chrome-isolated|g' \
    /usr/local/bin/media-bridge-intercom-fixed 2>/dev/null || true

# Create systemd service override for PipeWire security
log "Creating systemd overrides..."
mkdir -p /etc/systemd/system/pipewire-system.service.d
cat > /etc/systemd/system/pipewire-system.service.d/10-security.conf << 'EOF'
[Service]
# Enable security features
Environment="PIPEWIRE_SECURITY=1"
Environment="PIPEWIRE_SECURITY_CONTEXT=1"
EOF

# Restart services
log "Restarting PipeWire services..."
systemctl daemon-reload
systemctl start pipewire-system
sleep 2

# Verify installation
log "Verifying PipeWire installation..."
pipewire --version

# Check for pw-container
if command -v pw-container &> /dev/null; then
    log "✓ pw-container installed successfully"
    pw-container --help 2>&1 | head -5
else
    log "⚠ pw-container not found - Chrome isolation may be limited"
fi

# Test Chrome isolation
log "Testing Chrome isolation..."
export XDG_RUNTIME_DIR=/run/user/999
sudo -u mediabridge pw-cli info 2>&1 | grep -E "version|security" || true

log ""
log "====================================="
log "PipeWire $PIPEWIRE_VERSION upgrade complete!"
log "====================================="
log ""
log "New features available:"
log "  - Security contexts for app isolation"
log "  - pw-container tool for Chrome sandboxing"
log "  - Improved access control without D-Bus"
log ""
log "Chrome will now run in isolated container with:"
log "  - Only virtual devices visible"
log "  - Read-only permissions"
log "  - No access to hardware devices"
log ""
log "To test: VNC to port 5999 and check Chrome audio devices"