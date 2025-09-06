#!/bin/bash
# Full filesystem deployment script - syncs entire root from built image to live device
# This performs a complete filesystem replacement, ensuring device matches image exactly

set -e

# Configuration
DEVICE_IP="${1:-10.77.9.143}"
DEVICE_USER="root"
DEVICE_PASS="newlevel"
IMAGE_FILE="media-bridge.img"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (for mounting image)"
    echo "Usage: sudo $0 [DEVICE_IP]"
    exit 1
fi

# Check if image exists
if [ ! -f "$IMAGE_FILE" ]; then
    log_error "Image file $IMAGE_FILE not found!"
    log_info "Build an image first with: sudo ./build-image-for-rufus.sh"
    exit 1
fi

# Check if required tools are installed
for tool in sshpass rsync losetup kpartx; do
    if ! command -v $tool &> /dev/null; then
        log_error "$tool is required but not installed"
        case $tool in
            sshpass) log_info "Install with: apt-get install sshpass" ;;
            rsync) log_info "Install with: apt-get install rsync" ;;
            losetup) log_info "Install with: apt-get install util-linux" ;;
            kpartx) log_info "Install with: apt-get install kpartx" ;;
        esac
        exit 1
    fi
done

log_info "Full filesystem deployment from $IMAGE_FILE to device at $DEVICE_IP"
log_warn "This will completely replace the device's root filesystem!"
echo -n "Continue? (yes/no): "
read CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log_info "Aborted by user"
    exit 0
fi

# Function to run SSH command with proper handling of welcome-loop
run_ssh_command() {
    local cmd="$1"
    # Use -T to disable pseudo-tty allocation which prevents interactive programs
    # Use bash -c to ensure we get a non-interactive shell
    sshpass -p "$DEVICE_PASS" ssh -T -o StrictHostKeyChecking=no -o LogLevel=ERROR \
        $DEVICE_USER@$DEVICE_IP "bash -c '$cmd'"
}

# Check connection to device
log_info "Checking connection to $DEVICE_IP..."
if ! run_ssh_command "echo 'Connected'" &>/dev/null; then
    log_error "Cannot connect to device at $DEVICE_IP"
    exit 1
fi

# Create temporary mount directory
MOUNT_DIR=$(mktemp -d /tmp/media-bridge-deploy-XXXXXX)
trap "cleanup" EXIT

cleanup() {
    log_info "Cleaning up..."
    # Unmount if mounted
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        umount "$MOUNT_DIR" 2>/dev/null || true
    fi
    # Remove loop device mappings
    if [ -n "$LOOP_DEV" ]; then
        kpartx -d "$LOOP_DEV" 2>/dev/null || true
        losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
    # Remove temp directory
    rm -rf "$MOUNT_DIR" 2>/dev/null || true
}

# Setup loop device for image
log_info "Setting up loop device for image..."
LOOP_DEV=$(losetup --find --show "$IMAGE_FILE")
if [ -z "$LOOP_DEV" ]; then
    log_error "Failed to create loop device"
    exit 1
fi

# Create partition mappings
log_info "Creating partition mappings..."
kpartx -av "$LOOP_DEV"
sleep 2  # Give kernel time to create device nodes

# Find the root partition (typically second partition)
ROOT_PART="/dev/mapper/$(basename $LOOP_DEV)p2"
if [ ! -b "$ROOT_PART" ]; then
    log_error "Root partition not found at $ROOT_PART"
    exit 1
fi

# Mount the root partition
log_info "Mounting root partition..."
mount -o ro "$ROOT_PART" "$MOUNT_DIR"
if ! mountpoint -q "$MOUNT_DIR"; then
    log_error "Failed to mount root partition"
    exit 1
fi

# Verify image contents
log_info "Verifying image contents..."
if [ ! -d "$MOUNT_DIR/opt/media-bridge" ]; then
    log_error "Invalid image - missing /opt/media-bridge directory"
    exit 1
fi

# Get version from image
VERSION="unknown"
if [ -f "$MOUNT_DIR/etc/media-bridge/build-script-version" ]; then
    VERSION=$(cat "$MOUNT_DIR/etc/media-bridge/build-script-version")
    log_info "Image version: $VERSION"
fi

# Stop all services on device except SSH
log_info "Stopping all services on device (keeping SSH alive)..."
run_ssh_command '
# Get list of all active services except SSH and essential system services
SERVICES=$(systemctl list-units --state=active --type=service --no-legend | \
    grep -v -E "ssh|systemd-|dbus|networkd|resolved|timesyncd" | \
    awk "{print \$1}")

# Stop each service
for SERVICE in $SERVICES; do
    echo "Stopping $SERVICE..."
    systemctl stop "$SERVICE" 2>/dev/null || true
done

# Kill any remaining processes that might lock files (except SSH and system)
# Also kill any tmux sessions with welcome-loop
pkill -f media-bridge-welcome-loop 2>/dev/null || true
pkill -TERM -v -f "sshd|systemd|kernel" 2>/dev/null || true
sleep 2
pkill -KILL -v -f "sshd|systemd|kernel" 2>/dev/null || true

# Ensure filesystem is writable (Btrfs is always writable, but just in case)
mount -o remount,rw / 2>/dev/null || true

echo "Services stopped, ready for sync"
'

# Prepare rsync excludes
RSYNC_EXCLUDES="
--exclude=/proc/
--exclude=/sys/
--exclude=/dev/
--exclude=/run/
--exclude=/tmp/
--exclude=/mnt/
--exclude=/media/
--exclude=/var/run/
--exclude=/var/lock/
--exclude=/var/tmp/
--exclude=/home/*/
--exclude=/root/.ssh/
--exclude=/etc/ssh/ssh_host_*
--exclude=/etc/machine-id
--exclude=/var/lib/dbus/machine-id
--exclude=/etc/network/interfaces
--exclude=/etc/NetworkManager/system-connections/
"

# Perform full filesystem sync
log_info "Starting full filesystem sync (this may take 5-10 minutes)..."
log_info "Syncing from $MOUNT_DIR to $DEVICE_IP:/"

# Use rsync with SSH transport for the sync
# -a: archive mode (preserves everything)
# -x: don't cross filesystem boundaries
# -H: preserve hard links
# -A: preserve ACLs
# -X: preserve extended attributes
# --numeric-ids: don't map uid/gid values by user/group name
# --delete: delete files that don't exist in source
# --force: force deletion of directories even if not empty
# --progress: show progress
rsync -axHAX \
    --numeric-ids \
    --delete \
    --force \
    --progress \
    --stats \
    $RSYNC_EXCLUDES \
    -e "sshpass -p $DEVICE_PASS ssh -T -o StrictHostKeyChecking=no -o LogLevel=ERROR" \
    "$MOUNT_DIR/" \
    "$DEVICE_USER@$DEVICE_IP:/"

RSYNC_STATUS=$?

if [ $RSYNC_STATUS -ne 0 ]; then
    log_error "Rsync failed with status $RSYNC_STATUS"
    log_warn "Device may be in inconsistent state - manual recovery may be needed"
    exit 1
fi

log_info "Filesystem sync complete"

# Update fstab if needed (for proper boot)
log_info "Updating boot configuration..."
run_ssh_command '
# Regenerate machine ID
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup

# Update initramfs if needed
if command -v update-initramfs &>/dev/null; then
    update-initramfs -u 2>/dev/null || true
fi

# Sync filesystem
sync
sync
sync

echo "Boot configuration updated"
'

# Verify deployment
log_info "Verifying deployment..."
run_ssh_command '
echo "=== Version Info ==="
if [ -f /etc/media-bridge/build-script-version ]; then
    echo "Deployed version: $(cat /etc/media-bridge/build-script-version)"
fi

echo -e "\n=== Core Files ==="
ls -la /opt/media-bridge/ndi-* 2>/dev/null | head -5 || echo "Media Bridge binaries not found"

echo -e "\n=== System Info ==="
df -h / | grep -v Filesystem
uname -r
'

# Schedule reboot
log_info "Scheduling device reboot in 10 seconds..."
run_ssh_command "nohup sh -c 'sleep 10; reboot' &>/dev/null &" || true

log_success() { echo -e "${GREEN}===================================${NC}"; }

log_success
log_info "Full filesystem deployment complete!"
log_info "Device at $DEVICE_IP updated to version $VERSION"
log_info "Device will reboot in 10 seconds..."
log_success

log_info ""
log_info "After reboot (about 30-60 seconds), verify with:"
log_info "  sshpass -p $DEVICE_PASS ssh -T $DEVICE_USER@$DEVICE_IP 'media-bridge-info'"
log_info ""
log_warn "Note: First boot after full sync may take longer than usual"