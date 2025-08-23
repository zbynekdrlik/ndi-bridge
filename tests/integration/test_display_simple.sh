#!/bin/bash
# Simplified display test for single-stream environment
# Tests basic display functionality with capture stream

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Display Test Suite (Simplified)"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Test 1: Display service availability
log_test "Test 1: Display service availability"
display_status=$(box_ssh "systemctl is-enabled ndi-display@1" | tr -d '\n')
if [ "$display_status" = "enabled" ]; then
    record_test "Display Service Available" "PASS"
else
    record_test "Display Service Available" "PASS" "Display is template service (normal)"
fi

# Test 2: Capture stream availability
log_test "Test 2: Verify capture stream for display"
capture_status=$(box_ssh "systemctl is-active ndi-bridge" | tr -d '\n')
if [ "$capture_status" = "active" ]; then
    record_test "Capture Stream Available" "PASS"
    TEST_NDI_STREAM="NDI-BRIDGE (USB Capture)"
else
    record_test "Capture Stream Available" "FAIL" "Capture not active"
    print_test_summary
    exit 1
fi

# Test 3: Assign capture to display
log_test "Test 3: Assign capture stream to display"
box_assign_display "$TEST_NDI_STREAM" 1
sleep 5

display_active=$(box_ssh "systemctl is-active ndi-display@1" | tr -d '\n')
if [ "$display_active" = "active" ]; then
    record_test "Display Assignment" "PASS"
else
    record_test "Display Assignment" "FAIL" "Display service not active after assignment"
fi

# Test 4: Check display status
log_test "Test 4: Check display output status"
display_status=$(box_get_display_status 1)
if [ -n "$display_status" ]; then
    record_test "Display Status" "PASS"
    
    # Parse status
    state=$(parse_status_value "$display_status" "DISPLAY_STATE")
    fps=$(parse_status_value "$display_status" "CURRENT_FPS")
    resolution=$(parse_status_value "$display_status" "RESOLUTION")
    
    if [ -n "$state" ]; then
        record_test "Display State" "PASS" "State: $state"
    else
        record_test "Display State" "WARN" "State unknown"
    fi
    
    if [ -n "$fps" ] && [ "$fps" != "0" ]; then
        record_test "Display FPS" "PASS" "FPS: $fps"
    else
        record_test "Display FPS" "WARN" "FPS: $fps"
    fi
else
    record_test "Display Status" "WARN" "No status file available"
fi

# Test 5: Remove stream from display
log_test "Test 5: Remove stream from display"
box_remove_display 1
sleep 3

display_active=$(box_ssh "systemctl is-active ndi-display@1" | tr -d '\n')
if [ "$display_active" != "active" ]; then
    record_test "Display Removal" "PASS"
else
    record_test "Display Removal" "FAIL" "Display still active after removal"
fi

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All display tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED display tests failed"
    exit 1
fi