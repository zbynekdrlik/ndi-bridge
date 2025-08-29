#!/bin/bash
# Test suite for VDO.Ninja Intercom functionality
# MUST verify read-only filesystem and full functionality

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
DEVICE_IP="${1:-10.77.9.169}"
TEST_BOX_IP="${DEVICE_IP}"  # For compatibility with ro_check module
SSH_USER="root"
SSH_PASS="newlevel"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function for SSH commands
ssh_cmd() {
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$DEVICE_IP" "$1"
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
echo "VDO.Ninja Intercom Test Suite"
echo "Testing device: $DEVICE_IP"
echo "========================================="

# CRITICAL: Use the standard RO check module
echo -e "\n${YELLOW}CRITICAL CHECK: Filesystem Status${NC}"
if ! verify_readonly_filesystem "$DEVICE_IP"; then
    exit 1
fi

# Test 1: Service is enabled
echo -e "\n${YELLOW}Testing Service Configuration${NC}"

if ssh_cmd "systemctl is-enabled vdo-ninja-intercom.service" | grep -q "enabled"; then
    print_test_result "VDO.Ninja service is enabled" "PASS"
else
    print_test_result "VDO.Ninja service is enabled" "FAIL"
fi

# Test 2: Service is active
if ssh_cmd "systemctl is-active vdo-ninja-intercom.service" | grep -q "active"; then
    print_test_result "VDO.Ninja service is active" "PASS"
else
    print_test_result "VDO.Ninja service is active" "FAIL"
fi

# Test 3: Chrome is running (with retry for startup time)
echo -e "\n${YELLOW}Testing Chrome Process${NC}"

# Retry up to 3 times with 5 second delays for Chrome to start
CHROME_COUNT=0
for attempt in 1 2 3; do
    CHROME_COUNT=$(ssh_cmd "ps aux | grep -E 'google-chrome.*vdo\.ninja' | grep -v grep | wc -l")
    if [ "$CHROME_COUNT" -gt 0 ]; then
        break
    fi
    if [ $attempt -lt 3 ]; then
        echo "  Waiting for Chrome to start (attempt $attempt/3)..."
        sleep 5
    fi
done

if [ "$CHROME_COUNT" -gt 0 ]; then
    print_test_result "Chrome browser is running ($CHROME_COUNT processes)" "PASS"
else
    print_test_result "Chrome browser is running" "FAIL"
fi

# Test 4: Xvfb virtual display
echo -e "\n${YELLOW}Testing Display Components${NC}"

if ssh_cmd "ps aux | grep -q '[X]vfb :99'"; then
    print_test_result "Xvfb virtual display is running" "PASS"
else
    print_test_result "Xvfb virtual display is running" "FAIL"
fi

# Test 5: PipeWire audio system
echo -e "\n${YELLOW}Testing Audio System${NC}"

if ssh_cmd "ps aux | grep -q '[p]ipewire'"; then
    print_test_result "PipeWire audio system is running" "PASS"
else
    print_test_result "PipeWire audio system is running" "FAIL"
fi

if ssh_cmd "ps aux | grep -q '[w]ireplumber'"; then
    print_test_result "WirePlumber is running" "PASS"
else
    print_test_result "WirePlumber is running" "FAIL"
fi

# Test 6: USB Audio detection
echo -e "\n${YELLOW}Testing USB Audio Device${NC}"

USB_AUDIO=$(ssh_cmd "pactl list sinks 2>/dev/null | grep -c 'USB.*Audio' || echo 0")
if [ "$USB_AUDIO" -gt 0 ]; then
    print_test_result "USB Audio device detected" "PASS"
else
    print_test_result "USB Audio device detected" "FAIL"
    echo "  Note: This may fail if no USB audio device is connected"
fi

# Test 7: Chrome profile in tmpfs
echo -e "\n${YELLOW}Testing Chrome Profile Location${NC}"

if ssh_cmd "ls -d /tmp/chrome-vdo-profile 2>/dev/null" | grep -q "chrome-vdo-profile"; then
    print_test_result "Chrome profile in tmpfs (/tmp)" "PASS"
else
    print_test_result "Chrome profile in tmpfs (/tmp)" "FAIL"
fi

# Test 8: VNC accessibility
echo -e "\n${YELLOW}Testing Remote Access${NC}"

if ssh_cmd "netstat -tln | grep -q ':5999'"; then
    print_test_result "VNC server listening on port 5999" "PASS"
else
    print_test_result "VNC server listening on port 5999" "FAIL"
fi

# Test 9: Service restart resilience
echo -e "\n${YELLOW}Testing Service Resilience${NC}"

ssh_cmd "systemctl restart vdo-ninja-intercom.service" 2>/dev/null
echo "  Waiting for service to fully start..."
sleep 20  # Increased from 10 to give Chrome more time to start

if ssh_cmd "systemctl is-active vdo-ninja-intercom.service" | grep -q "active"; then
    print_test_result "Service restarts successfully" "PASS"
else
    print_test_result "Service restarts successfully" "FAIL"
fi

# Test 10: Check for crash/error patterns in logs
echo -e "\n${YELLOW}Testing for Errors${NC}"

ERROR_COUNT=$(ssh_cmd "journalctl -u vdo-ninja-intercom.service -n 100 --no-pager 2>/dev/null | grep -c 'Trace/breakpoint trap\|Segmentation fault\|core dumped'" || echo "0")
ERROR_COUNT=$(echo "$ERROR_COUNT" | head -1)  # Take only first line if multiple
if [ "$ERROR_COUNT" -eq 0 ] 2>/dev/null || [ "$ERROR_COUNT" = "0" ]; then
    print_test_result "No Chrome crashes detected" "PASS"
else
    print_test_result "No Chrome crashes detected" "FAIL"
    echo "  Found $ERROR_COUNT crash indicators in logs"
fi

# Test 11: Verify no write attempts to read-only paths
RO_ERRORS=$(ssh_cmd "journalctl -u vdo-ninja-intercom.service -n 100 --no-pager | grep -c 'Read-only file system' || echo 0")
# Some RO errors are expected (like inability to create .local in /root)
# But Chrome shouldn't crash because of them
if [ "$RO_ERRORS" -lt 10 ]; then
    print_test_result "Minimal read-only filesystem errors" "PASS"
else
    print_test_result "Minimal read-only filesystem errors" "FAIL"
    echo "  Found $RO_ERRORS read-only errors (should be < 10)"
fi

# Final Report
echo "========================================="
echo -e "${YELLOW}Test Summary${NC}"
echo "========================================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}ALL TESTS PASSED!${NC}"
    echo "VDO.Ninja intercom is fully functional with read-only filesystem"
    exit 0
else
    echo -e "\n${RED}SOME TESTS FAILED!${NC}"
    echo "Please check the failed tests above for details"
    exit 1
fi