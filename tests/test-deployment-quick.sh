#!/bin/bash
# Quick deployment test - verifies deployment and reboot in minimal time

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/assertions.sh"
source "${SCRIPT_DIR}/lib/box_control.sh"

# Configuration
TEST_BOX_IP="${1:-10.77.9.143}"
IMAGE_FILE="${2:-ndi-bridge.img}"

echo "================================"
echo "Quick Deployment Test"
echo "================================"
echo "Box: $TEST_BOX_IP"
echo "Image: $IMAGE_FILE"
echo ""

# Check image exists
if [ ! -f "$IMAGE_FILE" ]; then
    echo "❌ Image file not found"
    exit 1
fi

# Check connectivity
echo "Checking connectivity..."
if ! box_ping; then
    echo "❌ Box not reachable"
    exit 1
fi
echo "✅ Box is reachable"

# Get initial state
echo ""
echo "Initial state:"
initial_uptime=$(box_ssh "cat /proc/uptime | cut -d. -f1")
initial_version=$(box_ssh "cat /etc/ndi-bridge/build-script-version 2>/dev/null || echo unknown")
echo "  Uptime: ${initial_uptime}s"
echo "  Version: $initial_version"

# Deploy image
echo ""
echo "Deploying image (this takes 1-2 minutes)..."
if box_deploy_image "$IMAGE_FILE"; then
    echo "✅ Image deployed"
else
    echo "❌ Deployment failed"
    exit 1
fi

# Quick service check
echo ""
echo "Service status after deployment:"
bridge_status=$(box_service_status "ndi-bridge")
display_status=$(box_service_status "ndi-display@1")
echo "  ndi-bridge: $bridge_status"
echo "  ndi-display@1: $display_status"

# Reboot
echo ""
echo "Rebooting box..."
box_reboot

# Wait for box
echo "Waiting for box to come back online..."
if box_wait_for_boot; then
    echo "✅ Box is back online"
else
    echo "❌ Box did not come back after reboot"
    exit 1
fi

# Verify reboot happened
echo ""
echo "Post-reboot verification:"
new_uptime=$(box_ssh "cat /proc/uptime | cut -d. -f1")
new_version=$(box_ssh "cat /etc/ndi-bridge/build-script-version 2>/dev/null || echo unknown")
echo "  New uptime: ${new_uptime}s"
echo "  New version: $new_version"

if [ "$new_uptime" -lt "$initial_uptime" ]; then
    echo "✅ Reboot confirmed (uptime reset)"
else
    echo "❌ Reboot did NOT happen!"
    exit 1
fi

# Check services
echo ""
echo "Service status after reboot:"
bridge_status=$(box_service_status "ndi-bridge")
display_status=$(box_service_status "ndi-display@1")
capture_state=$(box_ssh "cat /var/run/ndi-bridge/capture_state 2>/dev/null || echo none")
echo "  ndi-bridge: $bridge_status"
echo "  ndi-display@1: $display_status"
echo "  capture state: $capture_state"

# Check time sync
echo ""
echo "Time synchronization:"
time_sync=$(box_get_time_sync_status | grep "TIME_SYNC:" | cut -d: -f2)
echo "  Status: $time_sync"

# Summary
echo ""
echo "================================"
if [ "$bridge_status" = "active" ] && [ "$new_uptime" -lt "$initial_uptime" ]; then
    echo "✅ DEPLOYMENT SUCCESSFUL!"
    echo "  - Image deployed"
    echo "  - Box rebooted"
    echo "  - Services running"
    echo "  - Time sync:$time_sync"
    exit 0
else
    echo "❌ DEPLOYMENT FAILED"
    echo "  Check logs for details"
    exit 1
fi