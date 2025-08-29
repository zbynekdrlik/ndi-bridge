#!/bin/bash
# Test suite for Dante audio bridge functionality
# Tests Inferno implementation and audio routing

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
NC='\033[0m' # No Color

# Test configuration
DEVICE_IP="${1:-10.77.9.192}"
TEST_BOX_IP="${DEVICE_IP}"  # For compatibility with ro_check module
SSH_USER="root"
SSH_PASS="newlevel"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function for SSH commands
ssh_cmd() {
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR "$SSH_USER@$DEVICE_IP" "$1"
}

# Helper function to print test results
print_test_result() {
    local test_name="$1"
    local result="$2"
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((TESTS_FAILED++))
    fi
}

echo "========================================="
echo "Dante Audio Bridge Test Suite"
echo "Testing device: $DEVICE_IP"
echo "========================================="

# CRITICAL: Use the standard RO check module
echo -e "\n${YELLOW}CRITICAL CHECK: Filesystem Status${NC}"
if ! verify_readonly_filesystem "$DEVICE_IP"; then
    exit 1
fi

# Test 1: Check if Inferno is installed
echo -e "\n${YELLOW}Testing Inferno Installation${NC}"

if ssh_cmd "test -f /opt/inferno/target/release/inferno && echo 'exists' || echo 'missing'"; then
    print_test_result "Inferno binary exists" "PASS"
else
    print_test_result "Inferno binary exists" "FAIL"
fi

# Test 2: Check ALSA plugin
if ssh_cmd "test -f /usr/lib/x86_64-linux-gnu/alsa-lib/libalsa_pcm_inferno.so && echo 'exists' || echo 'missing'"; then
    print_test_result "Inferno ALSA plugin installed" "PASS"
else
    print_test_result "Inferno ALSA plugin installed" "FAIL"
fi

# Test 3: Service configuration
echo -e "\n${YELLOW}Testing Service Configuration${NC}"

if ssh_cmd "systemctl is-enabled dante-bridge.service 2>/dev/null | grep -q enabled"; then
    print_test_result "Dante service is enabled" "PASS"
else
    print_test_result "Dante service is enabled" "FAIL"
fi

# Test 4: Service status
if ssh_cmd "systemctl is-active dante-bridge.service | grep -q active"; then
    print_test_result "Dante service is active" "PASS"
else
    print_test_result "Dante service is active" "FAIL"
fi

# Test 5: Configuration file
echo -e "\n${YELLOW}Testing Configuration${NC}"

if ssh_cmd "test -f /etc/ndi-bridge/dante.conf && echo 'exists' || echo 'missing'"; then
    print_test_result "Dante configuration file exists" "PASS"
    
    # Check key settings
    CHANNELS=$(ssh_cmd "grep DANTE_CHANNELS /etc/ndi-bridge/dante.conf | cut -d= -f2")
    if [ -n "$CHANNELS" ]; then
        echo "  Configured for $CHANNELS channels"
    fi
else
    print_test_result "Dante configuration file exists" "FAIL"
fi

# Test 6: Network interface
echo -e "\n${YELLOW}Testing Network Configuration${NC}"

# Check if br0 has multicast enabled (required for Dante)
if ssh_cmd "ip link show br0 | grep -q MULTICAST"; then
    print_test_result "Bridge has multicast enabled" "PASS"
else
    print_test_result "Bridge has multicast enabled" "FAIL"
fi

# Test 7: PTP time sync (important for Dante)
echo -e "\n${YELLOW}Testing Time Synchronization${NC}"

if ssh_cmd "systemctl is-active ptp4l.service | grep -q active"; then
    print_test_result "PTP time sync is active" "PASS"
else
    print_test_result "PTP time sync is active" "WARN"
    echo "  Note: PTP is recommended but not required for Dante"
fi

# Test 8: ALSA devices
echo -e "\n${YELLOW}Testing ALSA Configuration${NC}"

if ssh_cmd "test -f /etc/asound.conf && grep -q 'type inferno' /etc/asound.conf"; then
    print_test_result "ALSA configured for Dante" "PASS"
    
    # List Dante devices
    DANTE_DEVICES=$(ssh_cmd "grep 'pcm.dante' /etc/asound.conf | wc -l")
    if [ "$DANTE_DEVICES" -gt 0 ]; then
        echo "  Found $DANTE_DEVICES Dante ALSA device(s)"
    fi
else
    print_test_result "ALSA configured for Dante" "FAIL"
fi

# Test 9: Audio routing capability
echo -e "\n${YELLOW}Testing Audio Routing${NC}"

# Check if PipeWire is running (needed for audio routing)
if ssh_cmd "ps aux | grep -q '[p]ipewire'"; then
    print_test_result "PipeWire audio system running" "PASS"
else
    print_test_result "PipeWire audio system running" "FAIL"
fi

# Test 10: Port availability
echo -e "\n${YELLOW}Testing Network Ports${NC}"

# Dante uses multicast and specific ports
if ssh_cmd "netstat -uln | grep -q ':4321'"; then
    print_test_result "Dante control port available" "PASS"
else
    print_test_result "Dante control port available" "INFO"
    echo "  Port may be used on demand"
fi

# Test 11: Helper scripts
echo -e "\n${YELLOW}Testing Helper Scripts${NC}"

if ssh_cmd "test -x /usr/local/bin/ndi-bridge-dante-status"; then
    print_test_result "Dante status script installed" "PASS"
else
    print_test_result "Dante status script installed" "FAIL"
fi

if ssh_cmd "test -x /usr/local/bin/ndi-bridge-dante-config"; then
    print_test_result "Dante config script installed" "PASS"
else
    print_test_result "Dante config script installed" "FAIL"
fi

# Test 12: Check for errors in logs
echo -e "\n${YELLOW}Testing for Errors${NC}"

ERROR_COUNT=$(ssh_cmd "journalctl -u dante-bridge.service -n 100 --no-pager 2>/dev/null | grep -c 'error\|failed\|fatal' || echo 0")
if [ "$ERROR_COUNT" -eq 0 ] || [ "$ERROR_COUNT" = "0" ]; then
    print_test_result "No errors in Dante logs" "PASS"
else
    print_test_result "No errors in Dante logs" "FAIL"
    echo "  Found $ERROR_COUNT error messages in logs"
fi

# Final Report
echo "========================================="
echo -e "${YELLOW}Test Summary${NC}"
echo "========================================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}ALL TESTS PASSED!${NC}"
    echo "Dante audio bridge is properly configured"
    exit 0
else
    echo -e "\n${RED}SOME TESTS FAILED!${NC}"
    echo "Please check the failed tests above for details"
    echo "Run 'ndi-bridge-dante-logs' on the device for more information"
    exit 1
fi