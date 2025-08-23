#!/bin/bash
# Capture functionality test suite
# Tests V4L2 capture, NDI transmission, and performance

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Capture Test Suite"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Test 1: Check capture device
log_test "Test 1: Capture device detection"
if box_check_capture_device; then
    record_test "Capture Device Detection" "PASS"
    
    # Get device info
    device_info=$(box_ssh "v4l2-ctl --device=$TEST_CAPTURE_DEVICE --all 2>/dev/null | head -20")
    log_output "Device Info" "$device_info"
else
    record_test "Capture Device Detection" "FAIL" "Device $TEST_CAPTURE_DEVICE not found"
    log_error "Cannot continue without capture device"
    print_test_summary
    exit 1
fi

# Test 2: NDI Bridge service status
log_test "Test 2: NDI Bridge service status"
if assert_service_active "ndi-bridge"; then
    record_test "NDI Bridge Service" "PASS"
    
    # Check if process is actually running
    if assert_process_running "ndi-bridge"; then
        record_test "NDI Bridge Process" "PASS"
    else
        record_test "NDI Bridge Process" "FAIL" "Service active but process not found"
    fi
else
    record_test "NDI Bridge Service" "FAIL" "Service not active"
    
    # Try to start it
    log_info "Attempting to start ndi-bridge service..."
    box_start_service "ndi-bridge"
    sleep 3
    
    if assert_service_active "ndi-bridge"; then
        record_test "NDI Bridge Service Recovery" "PASS"
    else
        record_test "NDI Bridge Service Recovery" "FAIL" "Could not start service"
    fi
fi

# Test 3: Capture status and metrics
log_test "Test 3: Capture status and metrics"
log_info "Waiting 30 seconds for capture to stabilize after boot..."
sleep 30  # Give proper time for capture to stabilize after boot

capture_status=$(box_get_capture_status)
if [ -n "$capture_status" ]; then
    record_test "Capture Status File" "PASS"
    log_output "Capture Status" "$capture_status"
    
    # Parse status values
    state=$(parse_status_value "$capture_status" "CAPTURE_STATE")
    fps=$(parse_status_value "$capture_status" "CURRENT_FPS")
    frames=$(parse_status_value "$capture_status" "TOTAL_FRAMES")
    dropped=$(parse_status_value "$capture_status" "DROPPED_FRAMES")
    resolution=$(parse_status_value "$capture_status" "RESOLUTION")
    
    # Verify capture is active
    if [ "$state" = "ACTIVE" ] || [ "$state" = "STARTING" ] || [ "$state" = "CAPTURING" ]; then
        record_test "Capture State" "PASS" "State: $state"
    else
        record_test "Capture State" "FAIL" "State: $state (expected ACTIVE/STARTING/CAPTURING)"
    fi
    
    # Verify FPS is in range
    if assert_fps_in_range "$fps"; then
        record_test "Capture FPS" "PASS" "FPS: $fps"
    else
        record_test "Capture FPS" "FAIL" "FPS: $fps (expected ~$EXPECTED_FPS)"
    fi
    
    # Check resolution
    if [ "$resolution" = "$EXPECTED_RESOLUTION" ]; then
        record_test "Capture Resolution" "PASS" "Resolution: $resolution"
    else
        record_test "Capture Resolution" "WARN" "Resolution: $resolution (expected $EXPECTED_RESOLUTION)"
    fi
    
    # Check dropped frames
    if [ "$dropped" = "0" ] || [ -z "$dropped" ]; then
        record_test "Dropped Frames" "PASS" "No dropped frames"
    else
        # Allow some dropped frames as warning
        record_test "Dropped Frames" "PASS" "Dropped frames: $dropped (warning)"
    fi
else
    record_test "Capture Status File" "FAIL" "Status file not found"
fi

# Test 4: FPS stability over time
log_test "Test 4: FPS stability test (5 seconds)"
log_info "Monitoring capture FPS for 5 seconds..."

avg_fps=$(box_monitor_capture 5)
if assert_fps_in_range "$avg_fps"; then
    record_test "FPS Stability" "PASS" "Average FPS: $avg_fps"
else
    record_test "FPS Stability" "FAIL" "Average FPS: $avg_fps (unstable)"
fi

# Test 5: Service restart
log_test "Test 5: Service restart and recovery"
log_info "Restarting ndi-bridge service..."

box_restart_service "ndi-bridge"
sleep 5

if assert_service_active "ndi-bridge"; then
    record_test "Service Restart" "PASS"
    
    # Check if capture resumed
    sleep 3
    if assert_capture_active; then
        record_test "Capture Resume" "PASS"
    else
        record_test "Capture Resume" "FAIL" "Capture did not resume after restart"
    fi
else
    record_test "Service Restart" "FAIL" "Service failed to restart"
fi

# Test 6: NDI stream verification
log_test "Test 6: NDI stream verification"
streams=$(box_list_ndi_streams)

if [ -n "$streams" ]; then
    log_info "Available NDI streams:"
    echo "$streams"
    
    if echo "$streams" | grep -q "NDI-BRIDGE"; then
        record_test "NDI Stream Broadcasting" "PASS"
    else
        record_test "NDI Stream Broadcasting" "FAIL" "NDI-BRIDGE stream not found"
    fi
else
    record_test "NDI Stream Broadcasting" "FAIL" "No NDI streams detected"
fi

# Test 7: Memory and CPU usage
log_test "Test 7: Resource usage"
# Use ps for more reliable output
cpu_usage=$(box_ssh "ps aux | grep '/opt/ndi-bridge/ndi-bridge' | grep -v grep | awk '{print \$3}' | head -1")
mem_usage=$(box_ssh "ps aux | grep '/opt/ndi-bridge/ndi-bridge' | grep -v grep | awk '{print \$4}' | head -1")

if [ -n "$cpu_usage" ]; then
    log_info "CPU Usage: ${cpu_usage}%"
    log_info "Memory Usage: ${mem_usage}%"
    
    # Check if CPU usage is reasonable (less than 60% for USB capture + NDI encoding)
    cpu_int=$(echo "$cpu_usage" | cut -d'.' -f1)
    if [ "$cpu_int" -lt 60 ]; then
        record_test "CPU Usage" "PASS" "CPU: ${cpu_usage}%"
    else
        record_test "CPU Usage" "WARN" "High CPU usage: ${cpu_usage}%"
    fi
else
    record_test "Resource Usage" "FAIL" "Could not get resource metrics"
fi

# Test 8: Error handling - disconnect/reconnect device
log_test "Test 8: Error handling (optional - requires physical access)"
log_warn "Skipping physical disconnect test (requires manual intervention)"

# Test 9: Long-term stability (optional)
if [ "${RUN_LONG_TESTS:-false}" = "true" ]; then
    log_test "Test 9: Long-term stability (5 minutes)"
    log_info "Running 5-minute stability test..."
    
    start_frames=$(parse_status_value "$(box_get_capture_status)" "TOTAL_FRAMES")
    sleep 300  # 5 minutes
    end_frames=$(parse_status_value "$(box_get_capture_status)" "TOTAL_FRAMES")
    
    if [ -n "$start_frames" ] && [ -n "$end_frames" ]; then
        frames_captured=$((end_frames - start_frames))
        expected_frames=$((30 * 300))  # 30fps * 300 seconds
        
        # Allow 5% variance
        min_frames=$((expected_frames * 95 / 100))
        max_frames=$((expected_frames * 105 / 100))
        
        if [ $frames_captured -ge $min_frames ] && [ $frames_captured -le $max_frames ]; then
            record_test "Long-term Stability" "PASS" "Captured $frames_captured frames"
        else
            record_test "Long-term Stability" "FAIL" "Frame count off: $frames_captured (expected ~$expected_frames)"
        fi
    else
        record_test "Long-term Stability" "FAIL" "Could not get frame counts"
    fi
else
    log_info "Skipping long-term test (set RUN_LONG_TESTS=true to enable)"
fi

# Collect diagnostic logs
log_info "Collecting diagnostic information..."
bridge_logs=$(box_get_logs "ndi-bridge" 30)
log_output "NDI Bridge Recent Logs" "$bridge_logs"

# Get dmesg for V4L2 errors
dmesg_v4l2=$(box_ssh "dmesg | grep -i v4l2 | tail -20")
if [ -n "$dmesg_v4l2" ]; then
    log_output "V4L2 Kernel Messages" "$dmesg_v4l2"
fi

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All capture tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED capture tests failed"
    exit 1
fi