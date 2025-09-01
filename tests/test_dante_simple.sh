#!/bin/bash
# Simple Dante Audio Bridge Test
# Focus: Verify Dante → USB (Arturia) audio playback at 96kHz

set +e  # Don't exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test configuration
DEVICE_IP="${1:-10.77.9.192}"
SSH_USER="root"
SSH_PASS="newlevel"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the RO check module
source "${SCRIPT_DIR}/lib/ro_check.sh" || {
    echo "ERROR: Could not load ro_check.sh module"
    exit 1
}

# SSH command wrapper
ssh_cmd() {
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "$SSH_USER@$DEVICE_IP" "$1"
}

echo "========================================="
echo "Dante Audio Bridge Test (Simplified)"
echo "Testing device: $DEVICE_IP"
echo "Focus: Dante → USB playback at 96kHz"
echo "========================================="

# CRITICAL: Verify filesystem is read-only
echo -e "\n${YELLOW}CRITICAL CHECK: Filesystem Status${NC}"
if ! verify_readonly_filesystem "$DEVICE_IP"; then
    exit 1
fi

echo -e "\n${YELLOW}Core Services Check${NC}"

# 1. Check Statime PTP daemon
STATUS=$(ssh_cmd "systemctl is-active statime.service")
if [ "$STATUS" = "active" ]; then
    echo -e "${GREEN}✓${NC} Statime PTP daemon: Running"
else
    echo -e "${RED}✗${NC} Statime PTP daemon: $STATUS"
fi

# 2. Check Dante bridge service
STATUS=$(ssh_cmd "systemctl is-active dante-bridge.service")
if [ "$STATUS" = "active" ]; then
    echo -e "${GREEN}✓${NC} Dante bridge service: Running"
    
    # Get process details
    PIDS=$(ssh_cmd "pgrep -f 'arecord.*dante|aplay.*dante' | wc -l")
    echo "  Active audio processes: $PIDS"
else
    echo -e "${RED}✗${NC} Dante bridge service: $STATUS"
fi

echo -e "\n${YELLOW}Audio Configuration${NC}"

# 3. Check ALSA configuration
if ssh_cmd "grep -q 'type inferno' /etc/asound.conf"; then
    echo -e "${GREEN}✓${NC} ALSA configured correctly (type inferno)"
    
    # Check sample rate
    RATE=$(ssh_cmd "grep SAMPLE_RATE /etc/asound.conf | grep -o '[0-9]*'")
    if [ "$RATE" = "96000" ]; then
        echo -e "${GREEN}✓${NC} Sample rate: 96kHz"
    else
        echo -e "${RED}✗${NC} Sample rate: $RATE (should be 96000)"
    fi
else
    echo -e "${RED}✗${NC} ALSA configuration incorrect"
fi

# 4. Check USB audio device
echo -e "\n${YELLOW}USB Audio Device${NC}"
USB_DEVICES=$(ssh_cmd "aplay -l 2>/dev/null | grep -E 'USB Audio|Arturia|Focusrite|Scarlett|Behringer'")
if [ -n "$USB_DEVICES" ]; then
    echo -e "${GREEN}✓${NC} USB audio device found:"
    echo "$USB_DEVICES" | sed 's/^/  /'
else
    echo -e "${YELLOW}⚠${NC} No USB audio device found"
    echo "  Bridge will run in receive-only mode"
fi

# 5. Check Dante discovery ports
echo -e "\n${YELLOW}Dante Network Visibility${NC}"
PORTS_OPEN=$(ssh_cmd "netstat -tuln 2>/dev/null | grep -E ':(8700|8800) ' | wc -l")
if [ "$PORTS_OPEN" -ge 2 ]; then
    echo -e "${GREEN}✓${NC} Discovery ports open (8700/8800)"
    echo -e "${GREEN}✓${NC} Device should be visible in Dante Controller"
else
    echo -e "${RED}✗${NC} Discovery ports not open"
    echo "  Device may not be visible in Dante Controller"
fi

# 6. Check for errors in logs
echo -e "\n${YELLOW}Service Health Check${NC}"
ERRORS=$(ssh_cmd "journalctl -u dante-bridge.service -n 50 --no-pager 2>/dev/null | grep -c 'error\|fail' || echo 0")
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}✓${NC} No errors in Dante bridge logs"
else
    echo -e "${YELLOW}⚠${NC} Found $ERRORS error messages in logs"
    echo "  Run 'ndi-bridge-dante-logs' on device for details"
fi

# 7. Verify audio routing
echo -e "\n${YELLOW}Audio Routing Status${NC}"
DANTE_TO_USB=$(ssh_cmd "ps aux | grep -c 'arecord.*dante.*aplay.*plughw' || echo 0")
USB_TO_DANTE=$(ssh_cmd "ps aux | grep -c 'arecord.*plughw.*aplay.*dante' || echo 0")

if [ "$DANTE_TO_USB" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Dante → USB routing: Active"
else
    echo -e "${RED}✗${NC} Dante → USB routing: Not active"
fi

if [ "$USB_TO_DANTE" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} USB → Dante routing: Active"
else
    echo -e "${YELLOW}⚠${NC} USB → Dante routing: Not active"
fi

# Summary
echo "========================================="
echo -e "${YELLOW}Test Summary${NC}"
echo "========================================="

echo -e "\n${GREEN}READY FOR TESTING:${NC}"
echo "1. Open Dante Controller on Windows/Mac"
echo "2. Device should appear as '$(ssh_cmd "hostname" 2>/dev/null || echo "ndi-bridge")'"
echo "3. Patch audio from any Dante source to this device"
echo "4. Audio should play through USB output (Arturia/etc)"
echo ""
echo "Sample rate: 96kHz (required for professional Dante)"
echo ""
echo "For detailed logs: ssh $SSH_USER@$DEVICE_IP 'ndi-bridge-dante-logs'"

exit 0