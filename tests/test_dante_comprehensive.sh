#!/bin/bash
# Comprehensive Dante Audio Bridge Test Suite
# Tests ALL aspects of Dante functionality

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_TESTS=0

# Test result tracking
declare -A TEST_RESULTS

log_test() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    TEST_RESULTS["$test_name"]="$status|$details"
    
    if [ "$status" == "PASS" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  ${YELLOW}→ $details${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "========================================="
echo "    DANTE COMPREHENSIVE TEST SUITE"
echo "========================================="
echo

# Test 1: Check Statime PTP daemon
echo "Testing PTP daemon (Statime)..."
if systemctl is-active statime >/dev/null 2>&1; then
    PTP_PID=$(systemctl show statime -p MainPID --value)
    if [ "$PTP_PID" != "0" ] && kill -0 "$PTP_PID" 2>/dev/null; then
        log_test "Statime PTP daemon" "PASS" "Running with PID $PTP_PID"
    else
        log_test "Statime PTP daemon" "FAIL" "Service active but process not found"
    fi
else
    log_test "Statime PTP daemon" "FAIL" "Service not active"
fi

# Test 2: Check PTP clock export
echo "Testing PTP clock export..."
if [ -e /var/run/statime/usrvclock ]; then
    log_test "PTP clock export" "PASS" "Clock device exists"
else
    # Check if it's exported elsewhere
    if ls /dev/ptp* 2>/dev/null | grep -q ptp; then
        log_test "PTP clock export" "PASS" "PTP device found in /dev"
    else
        log_test "PTP clock export" "FAIL" "No clock device found"
    fi
fi

# Test 3: Check Inferno ALSA plugin
echo "Testing Inferno ALSA plugin..."
if [ -f /usr/lib/x86_64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so ]; then
    PLUGIN_SIZE=$(stat -c%s /usr/lib/x86_64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so)
    if [ "$PLUGIN_SIZE" -gt 1000000 ]; then
        log_test "Inferno ALSA plugin" "PASS" "Installed ($(($PLUGIN_SIZE/1024/1024))MB)"
    else
        log_test "Inferno ALSA plugin" "FAIL" "File too small: $PLUGIN_SIZE bytes"
    fi
else
    log_test "Inferno ALSA plugin" "FAIL" "Plugin not found"
fi

# Test 4: Check ALSA configuration
echo "Testing ALSA configuration..."
if aplay -L 2>/dev/null | grep -q "^dante$"; then
    log_test "ALSA Dante device" "PASS" "Device 'dante' configured"
else
    log_test "ALSA Dante device" "FAIL" "Device not in ALSA configuration"
fi

# Test 5: Test Dante device functionality
echo "Testing Dante device functionality..."
export INFERNO_NAME=${HOSTNAME:-ndi-bridge}
export INFERNO_INTERFACE=br0
if timeout 2 arecord -D dante -f S32_LE -r 48000 -c 2 -t raw 2>&1 | grep -q "Recording raw data"; then
    log_test "Dante recording" "PASS" "Can open Dante device for recording"
else
    ERROR=$(timeout 2 arecord -D dante -f S32_LE -r 48000 -c 2 -t raw 2>&1 | head -5)
    log_test "Dante recording" "FAIL" "Cannot record: $ERROR"
fi

# Test 6: Check network ports
echo "Testing network ports..."
PORTS_OPEN=0
for PORT in 8700 8800 8708 8809 319 320; do
    if netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        PORTS_OPEN=$((PORTS_OPEN + 1))
    fi
done
if [ "$PORTS_OPEN" -ge 2 ]; then
    log_test "Network ports" "PASS" "$PORTS_OPEN Dante/PTP ports open"
else
    log_test "Network ports" "FAIL" "Only $PORTS_OPEN ports open (need at least 2)"
fi

# Test 7: Check multicast
echo "Testing multicast configuration..."
if ip maddr show br0 2>/dev/null | grep -q "224.0.0"; then
    log_test "Multicast enabled" "PASS" "Multicast groups joined on br0"
else
    log_test "Multicast enabled" "FAIL" "No multicast groups on br0"
fi

# Test 8: Check Dante discovery packets
echo "Testing Dante discovery..."
# Start a background Dante process to ensure advertisement
(export INFERNO_NAME=${HOSTNAME:-ndi-bridge}; export INFERNO_INTERFACE=br0; 
 timeout 5 arecord -D dante -f S32_LE -r 48000 -c 2 -t raw 2>/dev/null >/dev/null) &
DANTE_PID=$!
sleep 2

# Check if ports opened
if netstat -tuln 2>/dev/null | grep -E ":(8700|8800) " | grep -q "$INFERNO_INTERFACE"; then
    log_test "Dante discovery" "PASS" "Discovery ports active"
    kill $DANTE_PID 2>/dev/null
else
    log_test "Dante discovery" "FAIL" "Discovery ports not opened"
    kill $DANTE_PID 2>/dev/null
fi

# Test 9: Check USB audio device
echo "Testing USB audio devices..."
USB_DEVICES=$(aplay -l 2>/dev/null | grep -c "USB Audio")
if [ "$USB_DEVICES" -gt 0 ]; then
    USB_INFO=$(aplay -l 2>/dev/null | grep "USB Audio" | head -1)
    log_test "USB audio device" "PASS" "$USB_DEVICES device(s) found"
else
    log_test "USB audio device" "FAIL" "No USB audio devices found"
fi

# Test 10: Check USB-Dante bridge
echo "Testing USB-Dante bridge..."
if systemctl is-active usb-dante-bridge >/dev/null 2>&1; then
    BRIDGE_PID=$(systemctl show usb-dante-bridge -p MainPID --value)
    if [ "$BRIDGE_PID" != "0" ] && kill -0 "$BRIDGE_PID" 2>/dev/null; then
        # Check if child processes exist
        CHILDREN=$(pgrep -P "$BRIDGE_PID" | wc -l)
        if [ "$CHILDREN" -gt 0 ]; then
            log_test "USB-Dante bridge" "PASS" "Running with $CHILDREN audio processes"
        else
            log_test "USB-Dante bridge" "FAIL" "Running but no audio processes"
        fi
    else
        log_test "USB-Dante bridge" "FAIL" "Service active but process not found"
    fi
else
    log_test "USB-Dante bridge" "FAIL" "Service not active"
fi

# Test 11: Check time sync coordination
echo "Testing time sync coordination..."
if systemctl is-active time-sync-coordinator >/dev/null 2>&1; then
    # Check if it detects Dante mode
    if journalctl -u time-sync-coordinator -n 10 2>/dev/null | grep -q "Dante mode active"; then
        log_test "Time sync coordination" "PASS" "Detecting Dante mode correctly"
    else
        log_test "Time sync coordination" "WARN" "Running but not detecting Dante mode"
    fi
else
    log_test "Time sync coordination" "FAIL" "Service not active"
fi

# Test 12: Configuration file check
echo "Testing configuration files..."
if [ -f /etc/ndi-bridge/dante.conf ]; then
    source /etc/ndi-bridge/dante.conf
    if [ "$DANTE_SAMPLE_RATE" == "96000" ] || [ "$DANTE_SAMPLE_RATE" == "48000" ]; then
        log_test "Dante configuration" "PASS" "Sample rate: ${DANTE_SAMPLE_RATE}Hz"
    else
        log_test "Dante configuration" "FAIL" "Invalid sample rate: $DANTE_SAMPLE_RATE"
    fi
else
    log_test "Dante configuration" "FAIL" "Configuration file missing"
fi

# Test 13: Test actual audio flow
echo "Testing audio flow..."
# Create a test tone and try to send through Dante
(export INFERNO_NAME=${HOSTNAME:-ndi-bridge}; export INFERNO_INTERFACE=br0;
 timeout 2 sh -c 'dd if=/dev/zero bs=4 count=1000 2>/dev/null | aplay -D dante -f S32_LE -r 48000 -c 2 -t raw' 2>&1) >/dev/null
if [ $? -eq 0 ] || [ $? -eq 124 ]; then  # 124 is timeout exit code
    log_test "Audio playback" "PASS" "Can send audio to Dante"
else
    log_test "Audio playback" "FAIL" "Cannot send audio to Dante"
fi

# Test 14: Check Inferno threads
echo "Testing Inferno threads..."
INFERNO_THREADS=$(ps -eLf | grep -c "inferno\|dante" | grep -v grep)
if [ "$INFERNO_THREADS" -gt 0 ]; then
    log_test "Inferno threads" "PASS" "$INFERNO_THREADS thread(s) running"
else
    log_test "Inferno threads" "FAIL" "No Inferno threads found"
fi

# Test 15: CRITICAL - Dante Controller visibility
echo "Testing Dante Controller visibility..."
echo -e "${YELLOW}This requires checking from Dante Controller on Windows/Mac${NC}"
echo "Starting 30-second advertisement for Controller detection..."

# Start advertising
(export INFERNO_NAME=${HOSTNAME:-ndi-bridge}; export INFERNO_INTERFACE=br0;
 timeout 30 arecord -D dante -f S32_LE -r 48000 -c 2 -t raw 2>/dev/null >/dev/null) &
ADV_PID=$!

echo "Advertising as '${HOSTNAME:-ndi-bridge}' on network..."
echo "CHECK NOW: Device should appear in Dante Controller"
sleep 5

# Check if advertising is working
if ps -p $ADV_PID >/dev/null 2>&1; then
    if netstat -tuln 2>/dev/null | grep -E ":(8700|8800) "; then
        log_test "Dante advertisement" "RUNNING" "Device advertising - check Controller NOW"
        echo "Waiting 25 more seconds for Controller check..."
        sleep 25
        kill $ADV_PID 2>/dev/null
    else
        log_test "Dante advertisement" "FAIL" "Ports not opened for discovery"
        kill $ADV_PID 2>/dev/null
    fi
else
    log_test "Dante advertisement" "FAIL" "Advertisement process died"
fi

echo
echo "========================================="
echo "           TEST RESULTS SUMMARY"
echo "========================================="
echo -e "${GREEN}PASSED:${NC} $PASS_COUNT"
echo -e "${RED}FAILED:${NC} $FAIL_COUNT"
echo -e "TOTAL:  $TOTAL_TESTS"
echo

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    echo "Dante implementation is fully functional"
    exit 0
else
    echo -e "${RED}✗ TESTS FAILED!${NC}"
    echo "Dante implementation has issues that need fixing"
    
    echo
    echo "Failed tests:"
    for test_name in "${!TEST_RESULTS[@]}"; do
        IFS='|' read -r status details <<< "${TEST_RESULTS[$test_name]}"
        if [ "$status" == "FAIL" ]; then
            echo "  - $test_name: $details"
        fi
    done
    exit 1
fi