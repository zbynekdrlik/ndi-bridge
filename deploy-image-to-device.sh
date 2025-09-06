#!/bin/bash
# Fast deployment script for Media Bridge device
# Syncs filesystem from built image to live device without reflashing
# Usage: ./deploy-image-to-device.sh [DEVICE_IP]

set -e

# Configuration
DEVICE_IP="${1:-10.77.9.143}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/scripts/deployment/full-filesystem-sync.sh"
LOG_FILE="/tmp/deploy-$(date +%Y%m%d-%H%M%S).log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if deployment script exists
if [ ! -f "$DEPLOY_SCRIPT" ]; then
    echo -e "${RED}[ERROR]${NC} Deployment script not found at: $DEPLOY_SCRIPT"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} This script must be run as root (for mounting image)"
    echo "Usage: sudo $0 [DEVICE_IP]"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Media Bridge Fast Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}[INFO]${NC} Target device: $DEVICE_IP"
echo -e "${GREEN}[INFO]${NC} Log file: $LOG_FILE"
echo -e "${YELLOW}[NOTE]${NC} This will sync the filesystem without reflashing USB"
echo ""

# Run deployment in background to prevent terminal timeouts
echo -e "${GREEN}[INFO]${NC} Starting deployment (runs in background to prevent timeouts)..."
echo "yes" | nohup "$DEPLOY_SCRIPT" "$DEVICE_IP" > "$LOG_FILE" 2>&1 &
DEPLOY_PID=$!

echo -e "${GREEN}[INFO]${NC} Deployment started with PID: $DEPLOY_PID"
echo ""
echo "Monitor progress with these commands:"
echo "  tail -f $LOG_FILE                # Full deployment log"
echo "  tail -f /tmp/rsync-deploy.log    # Rsync progress"
echo "  ps -p $DEPLOY_PID                 # Check if still running"
echo ""

# Monitor deployment for first 30 seconds to catch early errors
COUNTER=0
while [ $COUNTER -lt 30 ] && kill -0 $DEPLOY_PID 2>/dev/null; do
    sleep 2
    COUNTER=$((COUNTER + 2))
    
    # Check for early failures
    if grep -q "ERROR\|Failed to\|Cannot connect" "$LOG_FILE" 2>/dev/null; then
        echo ""
        echo -e "${RED}[ERROR]${NC} Deployment failed. Last lines from log:"
        tail -10 "$LOG_FILE"
        exit 1
    fi
    
    # Show progress dots
    echo -n "."
    
    # Show status at 10 second intervals
    if [ $((COUNTER % 10)) -eq 0 ]; then
        echo ""
        if grep -q "Rsync started" "$LOG_FILE" 2>/dev/null; then
            echo -e "${GREEN}[INFO]${NC} Filesystem sync in progress..."
        elif grep -q "Mounting root partition" "$LOG_FILE" 2>/dev/null; then
            echo -e "${GREEN}[INFO]${NC} Preparing image..."
        elif grep -q "Checking connection" "$LOG_FILE" 2>/dev/null; then
            echo -e "${GREEN}[INFO]${NC} Connecting to device..."
        fi
    fi
done

echo ""
if kill -0 $DEPLOY_PID 2>/dev/null; then
    echo -e "${GREEN}[INFO]${NC} Deployment is running successfully in background"
    echo -e "${YELLOW}[NOTE]${NC} Full sync typically takes 5-10 minutes"
    echo ""
    echo "Check final status with:"
    echo "  tail -50 $LOG_FILE | grep -E 'complete|success|fail|error' -i"
else
    # Check if it completed successfully
    if grep -q "Full filesystem deployment complete" "$LOG_FILE" 2>/dev/null; then
        VERSION=$(grep "Device at .* updated to version" "$LOG_FILE" | sed 's/.*version //')
        echo -e "${GREEN}[SUCCESS]${NC} Deployment completed! Version: $VERSION"
        echo -e "${GREEN}[INFO]${NC} Device is rebooting..."
        echo ""
        echo "Verify after reboot (30-60 seconds) with:"
        echo "  sshpass -p newlevel ssh root@$DEVICE_IP 'media-bridge-info'"
    else
        echo -e "${RED}[ERROR]${NC} Deployment stopped unexpectedly. Check log:"
        echo "  cat $LOG_FILE"
        exit 1
    fi
fi