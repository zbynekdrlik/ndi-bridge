#!/bin/bash
# NDI Bridge Intercom Test Suite
# Tests the intercom functionality including Chrome, audio, and VNC

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/box_control.sh"
source "$SCRIPT_DIR/../lib/ro_check.sh"

# Configuration from environment or defaults
TEST_BOX_IP="${TEST_BOX_IP:-10.77.9.143}"
SSH_USER="${SSH_USER:-root}"
SSH_PASS="${SSH_PASS:-newlevel}"
export SSHPASS="$SSH_PASS"

# Test suite header
log_test "Starting Intercom Test Suite"
log_info "Target box: $TEST_BOX_IP"

# Verify box is reachable
if ! ping -c 1 -W 2 "$TEST_BOX_IP" > /dev/null 2>&1; then
    log_error "Cannot reach test box at $TEST_BOX_IP"
    exit 1
fi

# Check readonly filesystem - required for valid test
if ! verify_readonly_filesystem "$TEST_BOX_IP"; then
    log_error "Failed to verify read-only filesystem"
    exit 1
fi

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Check intercom service status
log_test "Test 1: Intercom service status"
if box_ssh "systemctl is-active ndi-bridge-intercom.service" > /dev/null 2>&1; then
    log_info "✓ Intercom Service Active"
    ((TESTS_PASSED++))
else
    # Try to start it
    box_ssh "systemctl start ndi-bridge-intercom.service" > /dev/null 2>&1 || true
    sleep 5
    if box_ssh "systemctl is-active ndi-bridge-intercom.service" > /dev/null 2>&1; then
        log_info "✓ Intercom Service Started"
        ((TESTS_PASSED++))
    else
        log_error "✗ Intercom Service Failed"
        ((TESTS_FAILED++))
    fi
fi

# Test 2: Check Chrome process
log_test "Test 2: Chrome browser"
if box_ssh "pgrep -f 'chrome.*vdo.ninja'" > /dev/null 2>&1; then
    log_info "✓ Chrome Running"
    ((TESTS_PASSED++))
else
    log_error "✗ Chrome Not Running"
    ((TESTS_FAILED++))
fi

# Test 3: Check audio system (PipeWire or PulseAudio)
log_test "Test 3: Audio system"
if box_ssh "pgrep -f pipewire" > /dev/null 2>&1; then
    log_info "✓ PipeWire Running"
    ((TESTS_PASSED++))
elif box_ssh "pgrep -f pulseaudio" > /dev/null 2>&1; then
    log_info "✓ PulseAudio Running"
    ((TESTS_PASSED++))
else
    log_error "✗ No Audio System"
    ((TESTS_FAILED++))
fi

# Test 4: Check VNC server
log_test "Test 4: VNC server"
if box_ssh "pgrep -f x11vnc" > /dev/null 2>&1; then
    log_info "✓ VNC Server Running"
    
    # Check if VNC port is listening
    if box_ssh "netstat -tln | grep -q ':5999'" > /dev/null 2>&1; then
        log_info "✓ VNC Port 5999 Open"
        ((TESTS_PASSED++))
    else
        log_error "✗ VNC Port Not Open"
        ((TESTS_FAILED++))
    fi
else
    log_error "✗ VNC Server Not Running"
    ((TESTS_FAILED++))
fi

# Test 5: Check USB audio devices
log_test "Test 5: USB audio devices"
USB_AUDIO=$(box_ssh "pactl list sinks short 2>/dev/null | grep -E 'USB.*Audio|usb' | head -1" 2>/dev/null || true)
if [ -n "$USB_AUDIO" ]; then
    log_info "✓ USB Audio Device Found"
    log_info "Device: $(echo "$USB_AUDIO" | awk '{print $2}')"
    ((TESTS_PASSED++))
else
    log_warn "⚠ No USB Audio Device Found"
    # Not a failure as USB audio might not be connected
fi

# Test 6: Check intercom control script
log_test "Test 6: Intercom control script"
if box_ssh "test -x /usr/local/bin/ndi-bridge-intercom-control" > /dev/null 2>&1; then
    # Try to get status
    STATUS=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control status 2>/dev/null" || true)
    if [ -n "$STATUS" ] && echo "$STATUS" | grep -q "output"; then
        log_info "✓ Intercom Control Working"
        ((TESTS_PASSED++))
    else
        log_error "✗ Intercom Control Failed"
        ((TESTS_FAILED++))
    fi
else
    log_error "✗ Intercom Control Script Missing"
    ((TESTS_FAILED++))
fi

# Test 7: Check intercom configuration persistence
log_test "Test 7: Configuration persistence"
if box_ssh "test -f /etc/ndi-bridge/intercom.conf" > /dev/null 2>&1; then
    log_info "✓ Config File Exists"
    ((TESTS_PASSED++))
else
    log_info "○ No Saved Config (expected on first run)"
fi

# Test 8: Test audio control commands
log_test "Test 8: Audio control commands"
if box_ssh "test -x /usr/local/bin/ndi-bridge-intercom-control" > /dev/null 2>&1; then
    # Test volume set
    if box_ssh "/usr/local/bin/ndi-bridge-intercom-control set-volume output 50" > /dev/null 2>&1; then
        log_info "✓ Volume Control Working"
        ((TESTS_PASSED++))
    else
        log_warn "⚠ Volume Control Failed (might be no audio device)"
    fi
    
    # Test mute
    if box_ssh "/usr/local/bin/ndi-bridge-intercom-control mute output" > /dev/null 2>&1; then
        log_info "✓ Mute Control Working"
        ((TESTS_PASSED++))
    else
        log_warn "⚠ Mute Control Failed (might be no audio device)"
    fi
    
    # Test unmute
    if box_ssh "/usr/local/bin/ndi-bridge-intercom-control unmute output" > /dev/null 2>&1; then
        log_info "✓ Unmute Control Working"
        ((TESTS_PASSED++))
    else
        log_warn "⚠ Unmute Control Failed (might be no audio device)"
    fi
fi

# Test 9: Service restart
log_test "Test 9: Service restart"
log_info "Restarting intercom service..."
if box_restart_service "ndi-bridge-intercom"; then
    sleep 10  # Give Chrome time to start
    
    if box_ssh "pgrep -f 'chrome.*vdo.ninja'" > /dev/null 2>&1; then
        log_info "✓ Service Restart Successful"
        ((TESTS_PASSED++))
    else
        log_error "✗ Chrome Not Running After Restart"
        ((TESTS_FAILED++))
    fi
else
    log_error "✗ Service Restart Failed"
    ((TESTS_FAILED++))
fi

# Test 10: Check room connection
log_test "Test 10: VDO.Ninja room connection"
CHROME_LOG=$(box_ssh "journalctl -u ndi-bridge-intercom.service -n 50 --no-pager 2>/dev/null | grep -i 'room\\|vdo'" || true)
if echo "$CHROME_LOG" | grep -q "nl_interkom"; then
    log_info "✓ Connected to Room: nl_interkom"
    ((TESTS_PASSED++))
else
    log_warn "⚠ Cannot verify room connection"
fi

# Collect diagnostic information
log_info "Collecting diagnostic information..."
if [ "$VERBOSE" = "true" ]; then
    echo "=== Service Status ==="
    box_ssh "systemctl status ndi-bridge-intercom.service --no-pager | head -20" || true
    
    echo ""
    echo "=== Chrome Processes ==="
    box_ssh "ps aux | grep -i chrome | head -5" || true
    
    echo ""
    echo "=== Audio Devices ==="
    box_ssh "pactl list sinks short 2>/dev/null" || true
fi

# Summary
echo ""
echo "================================"
echo "Test Summary"
echo "================================"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    log_info "✅ All intercom tests passed!"
    verify_readonly_filesystem "$TEST_BOX_IP" > /dev/null 2>&1
    exit 0
else
    log_error "❌ $TESTS_FAILED intercom tests failed"
    
    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo ""
        echo "Failed Tests:"
        # List specific failures based on what failed
    fi
    
    verify_readonly_filesystem "$TEST_BOX_IP" > /dev/null 2>&1
    exit 1
fi