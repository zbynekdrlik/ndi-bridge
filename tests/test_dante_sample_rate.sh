#!/bin/bash
# Test Dante 96kHz Sample Rate Configuration

PASS=0
FAIL=0

echo "=== Dante 96kHz Sample Rate Test Suite ==="
echo

# Function to test a condition
test_check() {
    local description="$1"
    local command="$2"
    local expected="$3"
    
    echo -n "Testing: $description... "
    result=$(eval "$command" 2>&1)
    
    if [[ "$result" == *"$expected"* ]]; then
        echo "PASS"
        ((PASS++))
        return 0
    else
        echo "FAIL"
        echo "  Expected: $expected"
        echo "  Got: $result"
        ((FAIL++))
        return 1
    fi
}

# Test 1: Check ALSA configuration includes 96kHz
test_check "ALSA config has 96kHz" \
    "grep -E 'SAMPLE_RATE.*96000' /root/.asoundrc" \
    "SAMPLE_RATE 96000"

# Test 2: Check systemd services have environment variable
test_check "dante-advertiser has INFERNO_SAMPLE_RATE" \
    "grep INFERNO_SAMPLE_RATE /etc/systemd/system/dante-advertiser.service" \
    "INFERNO_SAMPLE_RATE=96000"

test_check "inferno-alsa has INFERNO_SAMPLE_RATE" \
    "grep INFERNO_SAMPLE_RATE /etc/systemd/system/inferno-alsa.service" \
    "INFERNO_SAMPLE_RATE=96000"

test_check "usb-dante-bridge has INFERNO_SAMPLE_RATE" \
    "grep INFERNO_SAMPLE_RATE /etc/systemd/system/usb-dante-bridge.service" \
    "INFERNO_SAMPLE_RATE=96000"

# Test 3: Check dante-advertiser script
test_check "dante-advertiser script exports 96kHz" \
    "grep 'INFERNO_SAMPLE_RATE.*96000' /usr/local/bin/dante-advertiser" \
    "INFERNO_SAMPLE_RATE"

# Test 4: Check running processes have environment variable
if pgrep -f "arecord.*dante" > /dev/null; then
    test_check "Running Dante process has 96kHz env" \
        "ps auxe | grep -E 'arecord.*dante' | grep -v grep" \
        "INFERNO_SAMPLE_RATE=96000"
else
    echo "Testing: Running Dante process... SKIP (not running)"
fi

# Test 5: Verify Dante discovery with 96kHz
echo -n "Testing: Dante device advertises with 96kHz... "
# Start a test instance with environment variable
INFERNO_NAME=test-96k INFERNO_SAMPLE_RATE=96000 INFERNO_INTERFACE=br0 \
    timeout 2 arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>&1 >/dev/null &
TEST_PID=$!
sleep 1

# Check if discovery ports opened
if netstat -tuln 2>/dev/null | grep -E ":(8700|8800) " | grep -q LISTEN; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL - Discovery ports not opened with 96kHz"
    ((FAIL++))
fi
kill $TEST_PID 2>/dev/null || true

# Test 6: Verify ALSA device accepts 96kHz
echo -n "Testing: ALSA dante device accepts 96kHz... "
if INFERNO_SAMPLE_RATE=96000 arecord -D dante -f S32_LE -r 96000 -c 2 -d 0.1 -t raw 2>&1 | grep -q "Recording"; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL - Cannot record at 96kHz"
    ((FAIL++))
fi

# Test 7: Check if 48kHz is rejected (should fail with mismatch)
echo -n "Testing: ALSA dante device rejects 48kHz... "
if INFERNO_SAMPLE_RATE=96000 arecord -D dante -f S32_LE -r 48000 -c 2 -d 0.1 -t raw 2>&1 | grep -qE "(rate|mismatch|error)"; then
    echo "PASS (correctly rejected)"
    ((PASS++))
else
    echo "WARNING - Device accepts mismatched rate"
fi

# Test 8: Verify environment propagation in systemctl
echo -n "Testing: systemctl show has environment variables... "
if systemctl show dante-advertiser.service 2>/dev/null | grep -q "INFERNO_SAMPLE_RATE=96000"; then
    echo "PASS"
    ((PASS++))
else
    echo "FAIL - Environment not in systemctl"
    ((FAIL++))
fi

echo
echo "=== Test Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ $FAIL -eq 0 ]; then
    echo "SUCCESS: All 96kHz sample rate tests passed!"
    exit 0
else
    echo "FAILURE: Some tests failed. Dante may not advertise at 96kHz."
    exit 1
fi