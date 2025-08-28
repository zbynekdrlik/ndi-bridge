#!/bin/bash
# Fast deployment script to update running NDI-Bridge box without USB reflashing
# This extracts the latest build from the image and deploys it to a running box

set -e

# Configuration
BOX_IP="${1:-10.77.9.143}"
BOX_USER="root"
BOX_PASS="newlevel"
IMAGE_FILE="ndi-bridge.img"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if image exists
if [ ! -f "$IMAGE_FILE" ]; then
    log_error "Image file $IMAGE_FILE not found!"
    log_info "Build an image first with: sudo ./build-image-for-rufus.sh"
    exit 1
fi

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    log_error "sshpass is required but not installed"
    log_info "Install with: sudo apt-get install sshpass"
    exit 1
fi

log_info "Deploying from image to box at $BOX_IP"

# Create temporary mount point
MOUNT_DIR=$(mktemp -d /tmp/ndi-deploy-XXXXXX)
trap "sudo umount $MOUNT_DIR 2>/dev/null; rm -rf $MOUNT_DIR" EXIT

# Mount the image (offset for second partition)
log_info "Mounting image..."
sudo mount -o loop,offset=537919488,ro "$IMAGE_FILE" "$MOUNT_DIR"

# Check connection to box
log_info "Checking connection to $BOX_IP..."
if ! sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -t \
    $BOX_USER@$BOX_IP "echo 'Connected'" &>/dev/null; then
    log_error "Cannot connect to box at $BOX_IP"
    exit 1
fi

# Make filesystem read-write on box
log_info "Making box filesystem read-write..."
sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no $BOX_USER@$BOX_IP \
    "mount -o remount,rw /"

# Function to deploy files
deploy_files() {
    local src="$1"
    local dest="$2"
    local desc="$3"
    
    log_info "Deploying $desc..."
    
    # Create tar archive and extract on remote
    # This preserves permissions and handles many files efficiently
    (cd "$MOUNT_DIR" && sudo tar czf - "$src" 2>/dev/null) | \
        sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no $BOX_USER@$BOX_IP \
        "cd / && tar xzf - 2>/dev/null"
}

# Stop services before deployment
log_info "Stopping services..."
sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no -t $BOX_USER@$BOX_IP << 'EOF'
systemctl stop ndi-bridge 2>/dev/null || true
systemctl stop ndi-display@0 ndi-display@1 ndi-display@2 2>/dev/null || true
systemctl stop ndi-bridge-collector 2>/dev/null || true
sleep 1
EOF

# Deploy core binaries
log_info "Deploying NDI-Bridge binaries..."
if [ -f "$MOUNT_DIR/opt/ndi-bridge/ndi-capture" ]; then
    sshpass -p "$BOX_PASS" scp -o StrictHostKeyChecking=no \
        "$MOUNT_DIR/opt/ndi-bridge/ndi-capture" \
        $BOX_USER@$BOX_IP:/opt/ndi-bridge/ndi-capture
    sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no $BOX_USER@$BOX_IP \
        "chmod +x /opt/ndi-bridge/ndi-capture"
fi

if [ -f "$MOUNT_DIR/opt/ndi-bridge/ndi-display" ]; then
    sshpass -p "$BOX_PASS" scp -o StrictHostKeyChecking=no \
        "$MOUNT_DIR/opt/ndi-bridge/ndi-display" \
        $BOX_USER@$BOX_IP:/opt/ndi-bridge/ndi-display
    sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no $BOX_USER@$BOX_IP \
        "chmod +x /opt/ndi-bridge/ndi-display"
fi

# Deploy helper scripts
log_info "Deploying helper scripts..."
for script in $MOUNT_DIR/usr/local/bin/ndi-bridge-*; do
    if [ -f "$script" ]; then
        script_name=$(basename "$script")
        sshpass -p "$BOX_PASS" scp -o StrictHostKeyChecking=no \
            "$script" $BOX_USER@$BOX_IP:/usr/local/bin/$script_name
    fi
done

# Deploy systemd service files
log_info "Deploying systemd services..."
for service in $MOUNT_DIR/etc/systemd/system/ndi-*.service \
               $MOUNT_DIR/etc/systemd/system/time-sync-*.service \
               $MOUNT_DIR/etc/systemd/system/setup-logs.service; do
    if [ -f "$service" ]; then
        service_name=$(basename "$service")
        sshpass -p "$BOX_PASS" scp -o StrictHostKeyChecking=no \
            "$service" $BOX_USER@$BOX_IP:/etc/systemd/system/$service_name
    fi
done

# Deploy configuration files
log_info "Deploying configuration..."
if [ -d "$MOUNT_DIR/etc/ndi-bridge" ]; then
    deploy_files "etc/ndi-bridge" "/etc/" "NDI configuration"
fi

# Update build version
if [ -f "$MOUNT_DIR/etc/ndi-bridge/build-script-version" ]; then
    VERSION=$(cat "$MOUNT_DIR/etc/ndi-bridge/build-script-version")
    log_info "Updating to version $VERSION"
fi

# Deploy web interface if it exists
if [ -d "$MOUNT_DIR/var/www/ndi-bridge" ]; then
    log_info "Deploying web interface..."
    deploy_files "var/www/ndi-bridge" "/var/www/" "web interface"
fi

# Install new packages if needed (for audio support)
log_info "Checking for required packages..."
sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no $BOX_USER@$BOX_IP << 'EOF'
# Check for ALSA packages
if ! dpkg -l | grep -q libasound2; then
    echo "Installing ALSA packages..."
    apt-get update
    apt-get install -y alsa-utils libasound2t64 2>/dev/null || \
    apt-get install -y alsa-utils libasound2 2>/dev/null || true
fi
EOF

# Reload systemd and restart services
log_info "Reloading services..."
sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no $BOX_USER@$BOX_IP << 'EOF'
systemctl daemon-reload

# Restart NDI services
systemctl restart ndi-bridge 2>/dev/null || true
systemctl restart ndi-bridge-collector 2>/dev/null || true

# Restart display services if they exist
for i in 0 1 2; do
    if systemctl is-enabled ndi-display@$i 2>/dev/null; then
        systemctl restart ndi-display@$i
    fi
done

# Restart welcome screen
systemctl restart ndi-welcome@tty2 2>/dev/null || true
EOF

# Make filesystem read-only again
log_info "Making filesystem read-only..."
sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no $BOX_USER@$BOX_IP \
    "sync && mount -o remount,ro / 2>/dev/null || true"

# Check status
log_info "Checking deployment status..."
sshpass -p "$BOX_PASS" ssh -o StrictHostKeyChecking=no $BOX_USER@$BOX_IP << 'EOF'
echo "=== Version Info ==="
/opt/ndi-bridge/ndi-bridge --version 2>/dev/null || echo "ndi-bridge not found"
/opt/ndi-bridge/ndi-display --version 2>&1 | head -3 || echo "ndi-display not found"

echo -e "\n=== Service Status ==="
systemctl is-active ndi-bridge || echo "ndi-bridge: inactive"
systemctl is-active ndi-display@1 2>/dev/null || echo "ndi-display@1: not configured"

echo -e "\n=== Audio Support ==="
which speaker-test &>/dev/null && echo "ALSA tools: installed" || echo "ALSA tools: missing"
ls -la /usr/lib/*/libasound.so* 2>/dev/null | head -1 || echo "ALSA library: missing"
EOF

log_info "Deployment complete!"
log_info "Box at $BOX_IP has been updated with the latest build"
log_info ""
log_info "To fully test all changes, you may want to reboot the box:"
log_info "  sshpass -p $BOX_PASS ssh $BOX_USER@$BOX_IP 'reboot'"