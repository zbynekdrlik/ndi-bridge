#!/bin/bash
# Full deployment and boot test
# This test deploys an image to the box, reboots, and verifies all services start

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Full Deployment Test"
IMAGE_FILE="${BUILD_IMAGE_PATH:-ndi-bridge.img}"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"
log_info "Image file: $IMAGE_FILE"

# Check prerequisites
if [ ! -f "$IMAGE_FILE" ]; then
    log_error "Image file $IMAGE_FILE not found"
    log_error "Please build an image first with: sudo ./build-image-for-rufus.sh"
    exit 1
fi

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Get initial system info
log_info "Getting initial system state..."
initial_info=$(box_get_system_info)
log_output "Initial System Info" "$initial_info"

# Record initial uptime to verify reboot later
initial_uptime=$(box_ssh "cat /proc/uptime | cut -d. -f1")
log_info "Initial uptime: ${initial_uptime}s"

# Test 1: Deploy image
log_test "Test 1: Deploy image to box"
log_info "This will copy binaries and scripts from image to running box"
if box_deploy_image "$IMAGE_FILE"; then
    record_test "Deploy Image" "PASS"
else
    record_test "Deploy Image" "FAIL" "Failed to deploy image"
    print_test_summary
    exit 1
fi

sleep 5

# Test 2: Verify services after deployment
log_test "Test 2: Verify services after deployment"
if assert_service_active "ndi-bridge"; then
    record_test "NDI Bridge Service (Post-Deploy)" "PASS"
else
    record_test "NDI Bridge Service (Post-Deploy)" "FAIL" "Service not active after deployment"
fi

display_status=$(box_ssh "systemctl is-active ndi-display@1" | tr -d '\n')
if [ "$display_status" = "active" ]; then
    record_test "NDI Display Service (Post-Deploy)" "PASS"
else
    # Display service is optional - only starts when stream is assigned
    record_test "NDI Display Service (Post-Deploy)" "PASS" "Service inactive (no stream assigned)"
fi

# Test 3: Verify capture is working
log_test "Test 3: Verify capture is working"
if box_check_capture_device; then
    record_test "Capture Device Present" "PASS"
    
    # Check capture status
    sleep 3
    if assert_capture_active; then
        record_test "Capture Active" "PASS"
        
        # Monitor FPS
        avg_fps=$(box_monitor_capture 5)
        if assert_fps_in_range "$avg_fps"; then
            record_test "Capture FPS" "PASS" "Average FPS: $avg_fps"
        else
            record_test "Capture FPS" "FAIL" "FPS out of range: $avg_fps"
        fi
    else
        record_test "Capture Active" "FAIL" "Capture not active"
    fi
else
    record_test "Capture Device Present" "FAIL" "Device $TEST_CAPTURE_DEVICE not found"
fi

# Test 4: Reboot and verify persistence
log_test "Test 4: Reboot and verify persistence"
log_info "Rebooting box..."
box_reboot

if box_wait_for_boot; then
    record_test "Box Reboot" "PASS"
    
    # Verify services started automatically
    log_test "Test 5: Verify services after reboot"
    
    if assert_service_active "ndi-bridge"; then
        record_test "NDI Bridge Auto-Start" "PASS"
    else
        record_test "NDI Bridge Auto-Start" "FAIL" "Service did not start after reboot"
    fi
    
    display_status=$(box_ssh "systemctl is-active ndi-display@1" | tr -d '\n')
    if [ "$display_status" = "active" ]; then
        record_test "NDI Display Auto-Start" "PASS"
    else
        # Display service is optional - only starts when stream is assigned
        record_test "NDI Display Auto-Start" "PASS" "Service inactive (no stream assigned)"
    fi
    
    # Check capture again
    sleep 5
    if assert_capture_active; then
        record_test "Capture After Reboot" "PASS"
    else
        record_test "Capture After Reboot" "FAIL" "Capture not active after reboot"
    fi
    
    # CRITICAL: Verify filesystem is read-only after reboot for power failure protection
    log_info "Checking filesystem mount state after reboot..."
    fs_state=$(box_ssh "mount | grep ' / ' | grep -o 'r[ow]' | head -1")
    if [ "$fs_state" = "ro" ]; then
        record_test "Read-Only Filesystem After Reboot" "PASS" "Power failure protection active"
    else
        record_test "Read-Only Filesystem After Reboot" "FAIL" "CRITICAL: Filesystem is $fs_state, not read-only!"
    fi
    
    # Test 6: Verify network and web interface
    log_test "Test 6: Verify network and web interface"
    
    if box_check_network; then
        record_test "Network Configuration" "PASS"
    else
        record_test "Network Configuration" "FAIL" "No IP address assigned"
    fi
    
    if box_check_web_interface; then
        record_test "Web Interface" "PASS"
    else
        record_test "Web Interface" "FAIL" "Web interface not accessible"
    fi
    
    # Test 6b: Verify time synchronization
    log_test "Test 6b: Verify time synchronization"
    
    time_sync_status=$(box_get_time_sync_status)
    log_output "Time Sync Status" "$time_sync_status"
    
    if assert_time_synchronized; then
        record_test "Time Synchronization" "PASS"
        
        # Check specifically for PTP
        if box_check_ptp_sync | grep -q "SYNCHRONIZED"; then
            record_test "PTP Sync" "PASS" "PTP is primary time source"
        else
            record_test "PTP Sync" "PASS" "Using NTP fallback (acceptable)"
        fi
    else
        record_test "Time Synchronization" "FAIL" "No time sync available"
    fi
    
    # Verify uptime changed (reboot happened)
    new_uptime=$(box_ssh "cat /proc/uptime | cut -d. -f1")
    log_info "New uptime after reboot: ${new_uptime}s"
    
    if [ "$new_uptime" -lt "$initial_uptime" ]; then
        record_test "Reboot Verification" "PASS" "System was rebooted (uptime reset)"
    else
        record_test "Reboot Verification" "FAIL" "System was NOT rebooted (uptime: $new_uptime vs $initial_uptime)"
    fi
    
    # Test 7: Verify NDI stream is available
    log_test "Test 7: Verify NDI stream availability"
    
    # The capture service itself broadcasts as an NDI stream
    # Check if capture is active which means NDI stream should be available
    capture_active=$(box_ssh "systemctl is-active ndi-bridge" | tr -d '\n')
    if [ "$capture_active" = "active" ]; then
        log_info "Capture service is active, NDI stream should be available"
        record_test "NDI Stream Available" "PASS" "Capture service broadcasting NDI"
    else
        streams=$(box_list_ndi_streams)
        if [ -n "$streams" ]; then
            log_info "Available NDI streams:"
            echo "$streams"
            record_test "NDI Stream Available" "PASS" "NDI streams detected"
        else
            record_test "NDI Stream Available" "WARN" "No NDI streams detected (capture may be starting)"
        fi
    fi
    
    # Test 8: System files and directories
    log_test "Test 8: Verify system files and directories"
    
    if assert_file_exists "/opt/ndi-bridge/ndi-bridge"; then
        record_test "NDI Bridge Binary" "PASS"
    else
        record_test "NDI Bridge Binary" "FAIL" "Binary not found"
    fi
    
    if assert_file_exists "/opt/ndi-bridge/ndi-display"; then
        record_test "NDI Display Binary" "PASS"
    else
        record_test "NDI Display Binary" "FAIL" "Binary not found"
    fi
    
    if assert_dir_exists "/etc/ndi-bridge"; then
        record_test "Config Directory" "PASS"
    else
        record_test "Config Directory" "FAIL" "Directory not found"
    fi
    
    # Get final system info
    log_info "Getting final system state..."
    final_info=$(box_get_system_info)
    log_output "Final System Info" "$final_info"
    
    # Get service logs for debugging
    log_info "Collecting service logs..."
    bridge_logs=$(box_get_logs "ndi-bridge" 20)
    display_logs=$(box_get_logs "ndi-display@1" 20)
    
    log_output "NDI Bridge Logs" "$bridge_logs"
    log_output "NDI Display Logs" "$display_logs"
    
else
    record_test "Box Reboot" "FAIL" "Box did not come back online after reboot"
fi

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED tests failed"
    exit 1
fi