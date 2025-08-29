#!/bin/bash
# Comprehensive system test suite for NDI Bridge
# Tests ALL features: capture, display, intercom, audio, network, Dante

# Don't exit on error - we want to run all tests
set +e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the RO check module
source "${SCRIPT_DIR}/lib/ro_check.sh" || {
    echo "ERROR: Could not load ro_check.sh module"
    exit 1
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
DEVICE_IP="${1:-10.77.9.192}"
TEST_BOX_IP="${DEVICE_IP}"  # For compatibility with ro_check module
SSH_USER="root"
SSH_PASS="newlevel"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# Helper function for SSH commands
ssh_cmd() {
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "$SSH_USER@$DEVICE_IP" "$1"
}

# Helper function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    case "$result" in
        PASS)
            echo -e "${GREEN}✓${NC} $test_name"
            [ -n "$details" ] && echo "  $details"
            ((TESTS_PASSED++))
            ;;
        FAIL)
            echo -e "${RED}✗${NC} $test_name"
            [ -n "$details" ] && echo "  ${RED}$details${NC}"
            ((TESTS_FAILED++))
            ;;
        WARN)
            echo -e "${YELLOW}⚠${NC} $test_name"
            [ -n "$details" ] && echo "  ${YELLOW}$details${NC}"
            ((TESTS_WARNED++))
            ;;
    esac
}

# Header
echo "============================================="
echo -e "${CYAN}   Comprehensive NDI Bridge System Test${NC}"
echo "============================================="
echo "Testing device: $DEVICE_IP"
echo "Date: $(date)"
echo

# CRITICAL: Verify filesystem is read-only
echo -e "\n${YELLOW}═══ CRITICAL: Filesystem Status ═══${NC}"
if ! verify_readonly_filesystem "$DEVICE_IP"; then
    exit 1
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 1: SYSTEM BASICS
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 1: System Basics ═══${NC}"

# Test network connectivity
if ping -c 1 -W 2 $DEVICE_IP >/dev/null 2>&1; then
    print_test_result "Network connectivity" "PASS"
else
    print_test_result "Network connectivity" "FAIL" "Cannot reach device"
    exit 1
fi

# Test SSH access
if ssh_cmd "echo test" >/dev/null 2>&1; then
    print_test_result "SSH access" "PASS"
else
    print_test_result "SSH access" "FAIL"
    exit 1
fi

# Check system version
VERSION=$(ssh_cmd "cat /etc/ndi-bridge-version 2>/dev/null || echo 'Unknown'")
print_test_result "System version" "PASS" "Version: $VERSION"

# Check uptime
UPTIME=$(ssh_cmd "uptime -p")
print_test_result "System uptime" "PASS" "$UPTIME"

# ═══════════════════════════════════════════════════════════════════
# SECTION 2: NETWORK CONFIGURATION
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 2: Network Configuration ═══${NC}"

# Test bridge interface
if ssh_cmd "ip link show br0" >/dev/null 2>&1; then
    print_test_result "Bridge interface (br0)" "PASS"
    
    # Get bridge details
    BR_MAC=$(ssh_cmd "ip link show br0 | grep ether | awk '{print \$2}'")
    BR_IP=$(ssh_cmd "ip -4 addr show br0 | grep inet | awk '{print \$2}'")
    echo "  Bridge MAC: $BR_MAC"
    echo "  Bridge IP: $BR_IP"
else
    print_test_result "Bridge interface (br0)" "FAIL"
fi

# Test physical interfaces
ETH_COUNT=$(ssh_cmd "ip link | grep -E '^[0-9]+: (eth|eno|enp)' | wc -l")
if [ "$ETH_COUNT" -ge 1 ]; then
    print_test_result "Physical ethernet interfaces" "PASS" "Found $ETH_COUNT interface(s)"
else
    print_test_result "Physical ethernet interfaces" "FAIL"
fi

# Test MAC persistence (from our fix)
ETH0_MAC=$(ssh_cmd "ip link show eth0 2>/dev/null | grep ether | awk '{print \$2}'")
BR0_MAC=$(ssh_cmd "ip link show br0 | grep ether | awk '{print \$2}'")
if [ "$ETH0_MAC" = "$BR0_MAC" ] && [ -n "$ETH0_MAC" ]; then
    print_test_result "MAC address inheritance" "PASS" "Bridge uses hardware MAC"
else
    print_test_result "MAC address inheritance" "WARN" "MACs don't match exactly"
fi

# Test mDNS/Avahi
if ssh_cmd "systemctl is-active avahi-daemon" | grep -q active; then
    print_test_result "mDNS/Avahi service" "PASS"
else
    print_test_result "mDNS/Avahi service" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 3: TIME SYNCHRONIZATION
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 3: Time Synchronization ═══${NC}"

# Test PTP
if ssh_cmd "systemctl is-active ptp4l" | grep -q active; then
    print_test_result "PTP time sync (ptp4l)" "PASS"
else
    print_test_result "PTP time sync (ptp4l)" "WARN" "Not critical but recommended"
fi

# Test PTP device
if ssh_cmd "test -e /dev/ptp0" && echo "exists"; then
    print_test_result "PTP device (/dev/ptp0)" "PASS"
else
    print_test_result "PTP device (/dev/ptp0)" "WARN" "May not have hardware support"
fi

# Test Chrony/NTP
if ssh_cmd "systemctl is-active chrony" | grep -q active; then
    print_test_result "NTP time sync (chrony)" "PASS"
else
    print_test_result "NTP time sync (chrony)" "WARN"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 4: NDI CAPTURE SERVICE
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 4: NDI Capture Service ═══${NC}"

# Test service enabled
if ssh_cmd "systemctl is-enabled ndi-capture" | grep -q enabled; then
    print_test_result "NDI capture service enabled" "PASS"
else
    print_test_result "NDI capture service enabled" "FAIL"
fi

# Test service active
if ssh_cmd "systemctl is-active ndi-capture" | grep -q active; then
    print_test_result "NDI capture service active" "PASS"
    
    # Get capture device info
    CAPTURE_DEV=$(ssh_cmd "v4l2-ctl --list-devices 2>/dev/null | head -5")
    if [ -n "$CAPTURE_DEV" ]; then
        echo "  Capture devices detected"
    fi
else
    print_test_result "NDI capture service active" "FAIL"
fi

# Test NDI binary
if ssh_cmd "test -x /opt/ndi-bridge/ndi-capture" && echo "exists"; then
    print_test_result "NDI capture binary" "PASS"
else
    print_test_result "NDI capture binary" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 5: NDI DISPLAY SERVICE
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 5: NDI Display Service ═══${NC}"

# Test display binary
if ssh_cmd "test -x /opt/ndi-bridge/ndi-display" && echo "exists"; then
    print_test_result "NDI display binary" "PASS"
else
    print_test_result "NDI display binary" "WARN" "Display feature may not be available"
fi

# Test display service
DISPLAY_STATUS=$(ssh_cmd "systemctl is-active ndi-display@1 2>/dev/null")
if [ "$DISPLAY_STATUS" = "active" ]; then
    print_test_result "NDI display service" "PASS"
else
    print_test_result "NDI display service" "WARN" "Not running (may be normal)"
fi

# Check for HDMI outputs
DRM_CARDS=$(ssh_cmd "ls /dev/dri/card* 2>/dev/null | wc -l")
if [ "$DRM_CARDS" -gt 0 ]; then
    print_test_result "Display outputs (DRM)" "PASS" "Found $DRM_CARDS output(s)"
else
    print_test_result "Display outputs (DRM)" "WARN" "No displays detected"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 6: AUDIO SUBSYSTEM
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 6: Audio Subsystem ═══${NC}"

# Test PipeWire
if ssh_cmd "ps aux | grep -q '[p]ipewire'"; then
    print_test_result "PipeWire audio system" "PASS"
else
    print_test_result "PipeWire audio system" "FAIL"
fi

# Test WirePlumber
if ssh_cmd "ps aux | grep -q '[w]ireplumber'"; then
    print_test_result "WirePlumber session manager" "PASS"
else
    print_test_result "WirePlumber session manager" "FAIL"
fi

# Test USB audio devices
USB_AUDIO_COUNT=$(ssh_cmd "aplay -l 2>/dev/null | grep -c USB")
if [ "$USB_AUDIO_COUNT" -gt 0 ]; then
    print_test_result "USB audio devices" "PASS" "Found $USB_AUDIO_COUNT device(s)"
    
    # List USB audio devices
    echo "  USB Audio Devices:"
    ssh_cmd "aplay -l | grep USB | sed 's/^/    /'"
    
    # Special check for Arturia
    if ssh_cmd "aplay -l | grep -q Arturia"; then
        echo -e "  ${GREEN}✓ Arturia USB device detected${NC}"
    fi
else
    print_test_result "USB audio devices" "WARN" "No USB audio devices found"
fi

# Test ALSA
if ssh_cmd "which aplay" >/dev/null 2>&1; then
    print_test_result "ALSA utilities" "PASS"
else
    print_test_result "ALSA utilities" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 7: VDO.NINJA INTERCOM
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 7: VDO.Ninja Intercom ═══${NC}"

# Test service enabled
if ssh_cmd "systemctl is-enabled vdo-ninja-intercom" | grep -q enabled; then
    print_test_result "Intercom service enabled" "PASS"
else
    print_test_result "Intercom service enabled" "FAIL"
fi

# Test service active
if ssh_cmd "systemctl is-active vdo-ninja-intercom" | grep -q active; then
    print_test_result "Intercom service active" "PASS"
else
    print_test_result "Intercom service active" "FAIL"
fi

# Test Chrome
CHROME_COUNT=$(ssh_cmd "ps aux | grep -E 'google-chrome.*vdo\\.ninja' | grep -v grep | wc -l")
if [ "$CHROME_COUNT" -gt 0 ]; then
    print_test_result "Chrome browser running" "PASS" "$CHROME_COUNT process(es)"
else
    print_test_result "Chrome browser running" "FAIL"
fi

# Test Xvfb display
if ssh_cmd "ps aux | grep -q '[X]vfb :99'"; then
    print_test_result "Xvfb virtual display" "PASS"
else
    print_test_result "Xvfb virtual display" "FAIL"
fi

# Test VNC access
if ssh_cmd "netstat -tln | grep -q ':5999'"; then
    print_test_result "VNC server (port 5999)" "PASS"
else
    print_test_result "VNC server (port 5999)" "FAIL"
fi

# Test Chrome profile
if ssh_cmd "ls -d /tmp/chrome-vdo-profile 2>/dev/null" | grep -q chrome; then
    print_test_result "Chrome profile in tmpfs" "PASS"
else
    print_test_result "Chrome profile in tmpfs" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 8: DANTE AUDIO BRIDGE
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 8: Dante Audio Bridge ═══${NC}"

# Test Statime PTP daemon
if ssh_cmd "systemctl is-enabled statime.service 2>/dev/null | grep -q enabled"; then
    print_test_result "Statime PTP daemon" "PASS"
    if ssh_cmd "systemctl is-active statime.service >/dev/null 2>&1"; then
        echo "  ✓ PTP synchronization active"
    else
        echo "  ⚠ Service enabled but not running"
    fi
else
    print_test_result "Statime PTP daemon" "WARN" "Not installed"
fi

# Test Inferno ALSA service
if ssh_cmd "systemctl is-enabled inferno-alsa.service 2>/dev/null | grep -q enabled"; then
    print_test_result "Inferno ALSA service" "PASS"
    if ssh_cmd "systemctl is-active inferno-alsa.service >/dev/null 2>&1"; then
        echo "  ✓ Dante device active"
        # Check if listening on Dante ports
        DANTE_PORTS=$(ssh_cmd "netstat -ulnp 2>/dev/null | grep -E '8700|8800' | wc -l")
        if [ "$DANTE_PORTS" -gt 0 ]; then
            echo "  ✓ Listening on Dante control ports"
        fi
    else
        echo "  ⚠ Service enabled but not running"
    fi
else
    print_test_result "Inferno ALSA service" "WARN" "Not installed"
fi

# Test USB-Dante bridge
if ssh_cmd "systemctl list-units --all | grep -q usb-dante-bridge"; then
    print_test_result "USB-Dante bridge" "PASS"
    if ssh_cmd "systemctl is-active usb-dante-bridge.service >/dev/null 2>&1"; then
        echo "  ✓ USB audio bridged to Dante"
    else
        echo "  ⚠ Service available but not active (may need USB device)"
    fi
else
    print_test_result "USB-Dante bridge" "WARN" "Not installed"
fi

# Test Inferno ALSA plugin
if ssh_cmd "test -f /usr/lib/x86_64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so"; then
    print_test_result "Inferno ALSA plugin" "PASS"
else
    print_test_result "Inferno ALSA plugin" "WARN" "Not installed"
fi

# Test Dante configuration
if ssh_cmd "test -f /etc/ndi-bridge/dante.conf" && echo "exists"; then
    print_test_result "Dante configuration" "PASS"
    
    # Show config details
    DANTE_MODE=$(ssh_cmd "grep DANTE_MODE /etc/ndi-bridge/dante.conf | cut -d= -f2")
    DANTE_CHANNELS=$(ssh_cmd "grep DANTE_CHANNELS /etc/ndi-bridge/dante.conf | cut -d= -f2")
    echo "  Mode: $DANTE_MODE, Channels: $DANTE_CHANNELS"
else
    print_test_result "Dante configuration" "WARN" "Not configured"
fi

# Test Dante helper scripts
if ssh_cmd "test -x /usr/local/bin/ndi-bridge-dante-status"; then
    print_test_result "Dante helper scripts" "PASS"
else
    print_test_result "Dante helper scripts" "WARN" "Scripts not installed"
fi

# Test multicast support (required for Dante)
if ssh_cmd "ip link show br0 | grep -q MULTICAST"; then
    print_test_result "Multicast support" "PASS" "Required for Dante"
else
    print_test_result "Multicast support" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 9: WEB INTERFACE
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 9: Web Interface ═══${NC}"

# Test nginx
if ssh_cmd "systemctl is-active nginx" | grep -q active; then
    print_test_result "Nginx web server" "PASS"
else
    print_test_result "Nginx web server" "FAIL"
fi

# Test wetty terminal
if ssh_cmd "systemctl is-active wetty" | grep -q active; then
    print_test_result "Wetty web terminal" "PASS"
else
    print_test_result "Wetty web terminal" "FAIL"
fi

# Test web ports
if ssh_cmd "netstat -tln | grep -q ':80 '"; then
    print_test_result "HTTP port (80)" "PASS"
else
    print_test_result "HTTP port (80)" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 10: SYSTEM RESOURCES
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 10: System Resources ═══${NC}"

# Check CPU usage
CPU_USAGE=$(ssh_cmd "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1")
if [ -n "$CPU_USAGE" ]; then
    print_test_result "CPU monitoring" "PASS" "Usage: ${CPU_USAGE}%"
else
    print_test_result "CPU monitoring" "WARN"
fi

# Check memory
MEM_INFO=$(ssh_cmd "free -h | grep Mem | awk '{print \"Total: \" \$2 \", Used: \" \$3 \", Free: \" \$4}'")
if [ -n "$MEM_INFO" ]; then
    print_test_result "Memory status" "PASS" "$MEM_INFO"
else
    print_test_result "Memory status" "WARN"
fi

# Check disk usage
DISK_USAGE=$(ssh_cmd "df -h / | tail -1 | awk '{print \"Used: \" \$3 \" of \" \$2 \" (\" \$5 \")\"}'")
if [ -n "$DISK_USAGE" ]; then
    print_test_result "Disk usage" "PASS" "$DISK_USAGE"
else
    print_test_result "Disk usage" "WARN"
fi

# Check tmpfs mounts
TMPFS_COUNT=$(ssh_cmd "mount | grep -c tmpfs")
if [ "$TMPFS_COUNT" -gt 0 ]; then
    print_test_result "Tmpfs mounts" "PASS" "Found $TMPFS_COUNT mount(s)"
else
    print_test_result "Tmpfs mounts" "WARN"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 11: HELPER COMMANDS
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 11: Helper Commands ═══${NC}"

# Test key helper scripts
HELPERS=(
    "ndi-bridge-info"
    "ndi-bridge-logs"
    "ndi-bridge-set-name"
    "ndi-bridge-help"
    "ndi-bridge-rw"
    "ndi-bridge-ro"
)

HELPER_COUNT=0
for helper in "${HELPERS[@]}"; do
    if ssh_cmd "which $helper" >/dev/null 2>&1; then
        ((HELPER_COUNT++))
    fi
done

if [ "$HELPER_COUNT" -eq "${#HELPERS[@]}" ]; then
    print_test_result "Helper commands" "PASS" "All ${#HELPERS[@]} commands available"
else
    print_test_result "Helper commands" "WARN" "Only $HELPER_COUNT of ${#HELPERS[@]} found"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 12: ERROR CHECKS
# ═══════════════════════════════════════════════════════════════════

echo -e "\n${CYAN}═══ Section 12: Error Checks ═══${NC}"

# Check for system errors
KERN_ERRORS=$(ssh_cmd "dmesg | grep -c -i 'error\|fail' | head -1" || echo "0")
if [ "$KERN_ERRORS" -lt 10 ]; then
    print_test_result "Kernel errors" "PASS" "Found $KERN_ERRORS error(s)"
else
    print_test_result "Kernel errors" "WARN" "Found $KERN_ERRORS error(s)"
fi

# Check for service failures
FAILED_SERVICES=$(ssh_cmd "systemctl list-units --failed --no-legend | wc -l")
if [ "$FAILED_SERVICES" -eq 0 ]; then
    print_test_result "Failed services" "PASS" "No failed services"
else
    print_test_result "Failed services" "FAIL" "$FAILED_SERVICES service(s) failed"
    ssh_cmd "systemctl list-units --failed --no-legend"
fi

# Check read-only filesystem errors
RO_ERRORS=$(ssh_cmd "journalctl -n 1000 | grep -c 'Read-only file system' || echo 0")
if [ "$RO_ERRORS" -lt 20 ]; then
    print_test_result "Read-only FS errors" "PASS" "Minimal ($RO_ERRORS)"
else
    print_test_result "Read-only FS errors" "WARN" "High count ($RO_ERRORS)"
fi

# ═══════════════════════════════════════════════════════════════════
# FINAL REPORT
# ═══════════════════════════════════════════════════════════════════

echo
echo "============================================="
echo -e "${CYAN}           Test Summary Report${NC}"
echo "============================================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Tests Warned: ${YELLOW}$TESTS_WARNED${NC}"
echo

# Calculate score
TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNED))
SCORE=$((TESTS_PASSED * 100 / TOTAL_TESTS))

echo -e "Overall Score: ${CYAN}${SCORE}%${NC}"
echo

# Final verdict
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        ALL CRITICAL TESTS PASSED!      ║${NC}"
    echo -e "${GREEN}║     System is fully operational        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    exit 0
elif [ $TESTS_FAILED -le 3 ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║    SYSTEM MOSTLY OPERATIONAL           ║${NC}"
    echo -e "${YELLOW}║    Some non-critical failures          ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════╝${NC}"
    exit 1
else
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║      CRITICAL FAILURES DETECTED        ║${NC}"
    echo -e "${RED}║     System needs attention             ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    exit 2
fi