#!/bin/bash
# Test for MAC address persistence and uniqueness
# This verifies that issue #27 is fixed - each device gets a unique, persistent MAC

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Device IP from argument
DEVICE_IP="${1:-}"

if [ -z "$DEVICE_IP" ]; then
    echo "Usage: $0 <device-ip>"
    echo "Example: $0 10.77.9.187"
    exit 1
fi

# Function to run SSH commands
ssh_cmd() {
    sshpass -p newlevel ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR -o ConnectTimeout=5 root@${DEVICE_IP} "$1"
}

# Function to print test results
print_test_result() {
    if [ "$2" = "PASS" ]; then
        echo -e "${GREEN}✓${NC} $1"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} $1"
        ((TESTS_FAILED++))
    fi
}

echo "========================================="
echo "MAC Address Persistence Test"
echo "Testing device: $DEVICE_IP"
echo "========================================="

# CRITICAL: First verify filesystem is read-only
echo -e "\n${YELLOW}CRITICAL CHECK: Filesystem Status${NC}"

RO_CHECK=$(ssh_cmd "mount | grep ' / ' | grep 'ro,' | wc -l" || echo "0")
if [ "$RO_CHECK" -gt 0 ]; then
    print_test_result "Filesystem is READ-ONLY (required for test validity)" "PASS"
else
    echo -e "${RED}FATAL ERROR: Filesystem is NOT read-only!${NC}"
    echo "Tests cannot proceed - filesystem must be read-only to ensure real-world conditions"
    echo "Run 'ndi-bridge-ro' on the device and try again"
    exit 1
fi

# Test 1: Check if MAC generation script exists
echo -e "\n${YELLOW}Testing MAC Generation Setup${NC}"

RESULT=$(ssh_cmd "test -f /usr/local/bin/generate-bridge-mac && echo 'exists'" || echo "")
if [ "$RESULT" = "exists" ]; then
    print_test_result "MAC generation script exists" "PASS"
else
    print_test_result "MAC generation script exists" "FAIL"
fi

# Test 2: Check if MAC configuration exists
RESULT=$(ssh_cmd "test -f /etc/systemd/network/10-br0.netdev.d/mac.conf && echo 'exists'" || echo "")
if [ "$RESULT" = "exists" ]; then
    print_test_result "MAC configuration file exists" "PASS"
else
    print_test_result "MAC configuration file exists" "FAIL"
    echo "  Note: Run manually with: mount -o remount,rw / && /usr/local/bin/generate-bridge-mac"
fi

# Test 3: Check if MAC is derived from hardware
echo -e "\n${YELLOW}Testing MAC Address Derivation${NC}"

# Get physical interface MACs
PHYSICAL_MACS=$(ssh_cmd "ip link show | grep -E '^[0-9]+: (eth|eno|enp)' -A1 | grep 'link/ether' | awk '{print \$2}'")
LOWEST_MAC=$(echo "$PHYSICAL_MACS" | sort | head -1)

if [ -n "$LOWEST_MAC" ]; then
    echo "  Lowest physical MAC: $LOWEST_MAC"
    
    # Get bridge MAC
    BRIDGE_MAC=$(ssh_cmd "ip link show br0 | grep 'link/ether' | awk '{print \$2}'")
    echo "  Bridge MAC: $BRIDGE_MAC"
    
    # Check if bridge MAC is locally administered (bit 0x02 set in first octet)
    FIRST_OCTET=$(echo "$BRIDGE_MAC" | cut -d: -f1)
    FIRST_OCTET_DEC=$((16#$FIRST_OCTET))
    
    if [ $((FIRST_OCTET_DEC & 0x02)) -eq 2 ]; then
        print_test_result "Bridge MAC is locally administered" "PASS"
    else
        print_test_result "Bridge MAC is locally administered" "FAIL"
    fi
    
    # Check if MAC is derived from lowest physical MAC
    LOWEST_BASE=$(echo "$LOWEST_MAC" | cut -d: -f2-6)
    BRIDGE_BASE=$(echo "$BRIDGE_MAC" | cut -d: -f2-6)
    
    if [ "$LOWEST_BASE" = "$BRIDGE_BASE" ]; then
        print_test_result "Bridge MAC derived from hardware MAC" "PASS"
    else
        print_test_result "Bridge MAC derived from hardware MAC" "FAIL"
    fi
else
    print_test_result "Could not determine physical MACs" "FAIL"
fi

# Test 4: Check if MAC persists in configuration
echo -e "\n${YELLOW}Testing MAC Persistence${NC}"

RESULT=$(ssh_cmd "test -f /etc/ndi-bridge-mac && echo 'exists'" || echo "")
if [ "$RESULT" = "exists" ]; then
    STORED_MAC=$(ssh_cmd "cat /etc/ndi-bridge-mac")
    CURRENT_MAC=$(ssh_cmd "ip link show br0 | grep 'link/ether' | awk '{print \$2}'")
    
    if [ "$STORED_MAC" = "$CURRENT_MAC" ]; then
        print_test_result "Stored MAC matches current MAC" "PASS"
    else
        print_test_result "Stored MAC matches current MAC" "FAIL"
        echo "  Stored: $STORED_MAC"
        echo "  Current: $CURRENT_MAC"
    fi
else
    print_test_result "MAC persistence file exists" "FAIL"
fi

# Test 5: Check systemd service
echo -e "\n${YELLOW}Testing Systemd Service${NC}"

SERVICE_STATUS=$(ssh_cmd "systemctl is-enabled generate-bridge-mac.service 2>/dev/null || echo 'not-found'")
if [ "$SERVICE_STATUS" = "enabled" ]; then
    print_test_result "MAC generation service is enabled" "PASS"
else
    print_test_result "MAC generation service is enabled" "FAIL"
    echo "  Status: $SERVICE_STATUS"
fi

# Test 6: Verify MAC is unique (not default)
echo -e "\n${YELLOW}Testing MAC Uniqueness${NC}"

CURRENT_MAC=$(ssh_cmd "ip link show br0 | grep 'link/ether' | awk '{print \$2}'")
# Check if MAC looks random/default (common patterns)
if [[ "$CURRENT_MAC" =~ ^(00:00:00|ff:ff:ff|aa:aa:aa|00:11:22) ]]; then
    print_test_result "MAC is unique (not default pattern)" "FAIL"
else
    print_test_result "MAC is unique (not default pattern)" "PASS"
fi

# Test 7: Simulate reboot persistence
echo -e "\n${YELLOW}Testing Reboot Simulation${NC}"

echo "  Getting current MAC and IP..."
CURRENT_MAC=$(ssh_cmd "ip link show br0 | grep 'link/ether' | awk '{print \$2}'")
CURRENT_IP=$(ssh_cmd "ip -4 addr show br0 | grep inet | awk '{print \$2}' | cut -d/ -f1")

echo "  Current MAC: $CURRENT_MAC"
echo "  Current IP: $CURRENT_IP"

# Check if configuration would survive reboot
if ssh_cmd "test -f /etc/systemd/network/10-br0.netdev.d/mac.conf && grep -q 'MACAddress=$CURRENT_MAC' /etc/systemd/network/10-br0.netdev.d/mac.conf"; then
    print_test_result "MAC configuration will persist after reboot" "PASS"
else
    print_test_result "MAC configuration will persist after reboot" "FAIL"
fi

# Final Report
echo "========================================="
echo -e "${YELLOW}Test Summary${NC}"
echo "========================================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}ALL TESTS PASSED!${NC}"
    echo "MAC address persistence is working correctly"
    echo "Each device will get a unique, hardware-derived MAC address"
    exit 0
else
    echo -e "\n${RED}SOME TESTS FAILED!${NC}"
    echo "MAC address persistence may not be fully functional"
    exit 1
fi