#!/bin/bash
# Test script to verify Dante discovery mechanism
# This tests that the simple arecord command triggers discovery port opening

set -e

echo "=== Dante Discovery Test Script ==="
echo "This script tests if the Dante device becomes visible in Dante Controller"
echo ""

# Check if running as root (needed for some operations)
if [ "$EUID" -ne 0 ]; then
    echo "Note: Running as non-root. Some checks may be limited."
fi

# Step 1: Check Inferno plugin is installed
echo "1. Checking Inferno ALSA plugin..."
if [ -f /usr/lib/x86_64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so ]; then
    echo "   ✓ Inferno plugin found"
else
    echo "   ✗ Inferno plugin NOT FOUND at /usr/lib/x86_64-linux-gnu/alsa-lib/"
    echo "   Run: ./scripts/compile-inferno.sh to build it"
    exit 1
fi

# Step 2: Check ALSA configuration
echo ""
echo "2. Checking ALSA configuration..."
if [ -f /root/.asoundrc ] || [ -f /etc/asound.conf ]; then
    if grep -q "type inferno" /root/.asoundrc 2>/dev/null || grep -q "type inferno" /etc/asound.conf 2>/dev/null; then
        echo "   ✓ ALSA configured with 'type inferno'"
    else
        echo "   ✗ ALSA not configured correctly (must use 'type inferno')"
        exit 1
    fi
else
    echo "   ✗ No ALSA configuration found"
    echo "   Creating test configuration..."
    cat > /tmp/test-asoundrc << 'EOF'
pcm.dante {
    type inferno
    RX_CHANNELS 2
    TX_CHANNELS 2
    SAMPLE_RATE 96000
    DEVICE_NAME "media-bridge-test"
    INTERFACE "br0"
}
EOF
    export ALSA_CONFIG_PATH=/tmp/test-asoundrc
    echo "   Created temporary config at /tmp/test-asoundrc"
fi

# Step 3: Check if dante device appears in ALSA
echo ""
echo "3. Checking if 'dante' device is available..."
if aplay -L 2>/dev/null | grep -q "^dante$"; then
    echo "   ✓ Dante device found in ALSA"
else
    echo "   ✗ Dante device not listed by ALSA"
    echo "   Inferno plugin may not be loading correctly"
fi

# Step 4: Check network interface
echo ""
echo "4. Checking network interface..."
if ip link show br0 >/dev/null 2>&1; then
    echo "   ✓ Bridge interface br0 exists"
    IP_ADDR=$(ip -4 addr show br0 | grep inet | awk '{print $2}' | cut -d/ -f1)
    echo "   IP Address: ${IP_ADDR:-not assigned}"
else
    echo "   ✗ Bridge interface br0 not found"
    echo "   Trying fallback to eth0..."
    if ip link show eth0 >/dev/null 2>&1; then
        echo "   Note: eth0 found, but Dante typically needs br0"
    fi
fi

# Step 5: Check if Statime is available
echo ""
echo "5. Checking Statime PTP daemon..."
if [ -f /usr/local/bin/statime ]; then
    echo "   ✓ Statime binary found"
    if systemctl is-active --quiet statime.service 2>/dev/null; then
        echo "   ✓ Statime service is running"
    else
        echo "   ⚠ Statime service not running"
        echo "   Starting it may help with discovery"
    fi
else
    echo "   ✗ Statime not found at /usr/local/bin/statime"
    echo "   PTP sync required for Dante"
fi

# Step 6: Test discovery port opening
echo ""
echo "6. Testing Dante discovery mechanism..."
echo "   Running: arecord -D dante -f S32_LE -r 96000 -c 2 -d 1 ..."

# Check ports before
PORTS_BEFORE=$(netstat -uln 2>/dev/null | grep -E ":(8700|8701|8800|8801) " | wc -l)

# Run the command that should trigger discovery
timeout 2 arecord -D dante -f S32_LE -r 96000 -c 2 -d 1 -t raw 2>/dev/null >/dev/null &
ARECORD_PID=$!

# Give it time to initialize
sleep 1

# Check if discovery ports opened
echo ""
echo "7. Checking discovery ports..."
netstat -uln 2>/dev/null | grep -E ":(8700|8701|8800|8801) " | while read line; do
    echo "   ✓ Port opened: $line"
done

PORTS_AFTER=$(netstat -uln 2>/dev/null | grep -E ":(8700|8701|8800|8801) " | wc -l)

if [ "$PORTS_AFTER" -gt "$PORTS_BEFORE" ]; then
    echo "   ✓ Discovery ports opened successfully!"
    echo ""
    echo "=== SUCCESS ==="
    echo "Device should now be visible in Dante Controller as 'media-bridge'"
    echo ""
    echo "To keep it running for testing:"
    echo "  arecord -D dante -f S32_LE -r 96000 -c 2 -t raw | aplay -D plughw:2,0 -f S32_LE -r 96000 -c 2 -t raw"
else
    echo "   ✗ Discovery ports did not open"
    echo ""
    echo "=== TROUBLESHOOTING ==="
    echo "1. Check if Inferno compiled correctly from GitLab"
    echo "2. Verify ALSA config has 'type inferno' (not 'type plug')"
    echo "3. Ensure network interface br0 exists and has IP"
    echo "4. Try running as root if not already"
    echo "5. Check system logs: journalctl -f"
fi

# Kill the test process
kill $ARECORD_PID 2>/dev/null || true

echo ""
echo "Test complete."