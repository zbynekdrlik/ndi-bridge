#!/bin/bash
# Quick deployment script for testing changes on running box
# Much simpler and faster than full image deployment

set -e

# Configuration
BOX_IP="${1:-10.77.9.143}"
IMAGE_FILE="media-bridge.img"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Quick Deploy to $BOX_IP${NC}"

# Check image exists
if [ ! -f "$IMAGE_FILE" ]; then
    echo -e "${RED}Error: $IMAGE_FILE not found${NC}"
    exit 1
fi

# Mount image
echo "Mounting image..."
MOUNT_DIR=$(mktemp -d)
trap "sudo umount $MOUNT_DIR 2>/dev/null; rm -rf $MOUNT_DIR" EXIT
sudo mount -o loop,offset=537919488,ro "$IMAGE_FILE" "$MOUNT_DIR"

# Deploy binaries only (fastest for testing)
echo "Deploying binaries..."
sshpass -p newlevel ssh root@$BOX_IP "systemctl stop ndi-capture ndi-display@1 2>/dev/null || true"
sleep 1

# Copy binaries
sshpass -p newlevel scp $MOUNT_DIR/opt/media-bridge/ndi-capture root@$BOX_IP:/opt/media-bridge/ 2>/dev/null || echo "ndi-capture not updated"
sshpass -p newlevel scp $MOUNT_DIR/opt/media-bridge/ndi-display root@$BOX_IP:/opt/media-bridge/ 2>/dev/null || echo "ndi-display not updated"

# Copy critical scripts
echo "Deploying scripts..."
sshpass -p newlevel scp $MOUNT_DIR/usr/local/bin/media-bridge-welcome root@$BOX_IP:/usr/local/bin/ 2>/dev/null || true
sshpass -p newlevel scp $MOUNT_DIR/usr/local/bin/media-bridge-info root@$BOX_IP:/usr/local/bin/ 2>/dev/null || true

# Restart services
echo "Restarting services..."
sshpass -p newlevel ssh root@$BOX_IP "systemctl start ndi-capture ndi-display@1 2>/dev/null || true"

# Quick status check
echo -e "\n${GREEN}Deployment Status:${NC}"
sshpass -p newlevel ssh root@$BOX_IP << 'EOF' 2>/dev/null | grep -v "Media Bridge Status"
echo "ndi-capture version: $(/opt/media-bridge/ndi-capture --version 2>/dev/null || echo 'error')"
echo "ndi-display version: $(/opt/media-bridge/ndi-display --version 2>&1 | head -1 || echo 'error')"
echo "Services:"
systemctl is-active ndi-capture 2>/dev/null || echo "ndi-capture: stopped"
systemctl is-active ndi-display@1 2>/dev/null || echo "ndi-display@1: stopped"
EOF

echo -e "${GREEN}Done!${NC}"