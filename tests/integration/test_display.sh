#!/bin/bash
# Display functionality test suite
# Tests NDI stream assignment, display output, and switching

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Display Test Suite"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"
log_info "Test stream: $TEST_NDI_STREAM"
log_info "Test display: $TEST_DISPLAY_ID"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Test 1: Display service initial state
log_test "Test 1: Display service initial state"

# Check if display service is running
if box_service_status "ndi-display@${TEST_DISPLAY_ID}" | grep -q "active"; then
    log_info "Display $TEST_DISPLAY_ID is already active"
    
    # Stop it for clean test
    box_stop_service "ndi-display@${TEST_DISPLAY_ID}"
    sleep 2
    record_test "Display Initial State" "PASS" "Display stopped for clean test"
else
    record_test "Display Initial State" "PASS" "Display not active (clean state)"
fi

# Test 2: List available NDI streams
log_test "Test 2: List available NDI streams"

streams=$(box_list_ndi_streams)
if [ -n "$streams" ]; then
    record_test "NDI Stream Discovery" "PASS"
    log_info "Available NDI streams:"
    echo "$streams"
    
    # Use the first available stream for testing
    FIRST_STREAM=$(echo "$streams" | head -1)
    if [ -n "$FIRST_STREAM" ]; then
        TEST_NDI_STREAM="$FIRST_STREAM"
        log_info "Using stream for testing: $TEST_NDI_STREAM"
        record_test "Test Stream Available" "PASS" "Using: $TEST_NDI_STREAM"
    else
        record_test "Test Stream Available" "FAIL" "No usable streams found"
        log_warn "Will continue with capture stream"
        TEST_NDI_STREAM="NDI-BRIDGE (USB Capture)"
    fi
else
    record_test "NDI Stream Discovery" "FAIL" "No NDI streams found"
    log_error "Cannot continue without NDI streams"
    print_test_summary
    exit 1
fi

# Test 3: Assign NDI stream to display
log_test "Test 3: Assign NDI stream to display"

if box_assign_display "$TEST_NDI_STREAM" "$TEST_DISPLAY_ID"; then
    record_test "Stream Assignment" "PASS"
    
    # Verify service is active
    if assert_service_active "ndi-display@${TEST_DISPLAY_ID}"; then
        record_test "Display Service Start" "PASS"
    else
        record_test "Display Service Start" "FAIL" "Service did not start"
    fi
else
    record_test "Stream Assignment" "FAIL" "Could not assign stream"
fi

# Test 4: Verify display status
log_test "Test 4: Verify display status"
sleep 5  # Give time for stream to establish

display_status=$(box_get_display_status "$TEST_DISPLAY_ID")
if [ -n "$display_status" ]; then
    record_test "Display Status File" "PASS"
    log_output "Display Status" "$display_status"
    
    # Parse status values
    stream_name=$(parse_status_value "$display_status" "STREAM_NAME")
    resolution=$(parse_status_value "$display_status" "RESOLUTION")
    fps=$(parse_status_value "$display_status" "FPS")
    frames=$(parse_status_value "$display_status" "FRAMES_RECEIVED")
    audio_channels=$(parse_status_value "$display_status" "AUDIO_CHANNELS")
    audio_rate=$(parse_status_value "$display_status" "AUDIO_SAMPLE_RATE")
    
    # Verify stream name
    if [ "$stream_name" = "$TEST_NDI_STREAM" ]; then
        record_test "Stream Name Match" "PASS" "Stream: $stream_name"
    else
        record_test "Stream Name Match" "WARN" "Stream: $stream_name (expected $TEST_NDI_STREAM)"
    fi
    
    # Verify video is being received
    if [ -n "$resolution" ] && [ "$resolution" != "0x0" ]; then
        record_test "Video Reception" "PASS" "Resolution: $resolution"
    else
        record_test "Video Reception" "FAIL" "No video (resolution: $resolution)"
    fi
    
    # Check FPS
    if [ -n "$fps" ] && [ "$fps" != "0" ]; then
        record_test "Video FPS" "PASS" "FPS: $fps"
    else
        record_test "Video FPS" "FAIL" "No FPS data"
    fi
    
    # Check audio (if stream has audio)
    if [ -n "$audio_channels" ] && [ "$audio_channels" != "0" ]; then
        record_test "Audio Reception" "PASS" "Audio: ${audio_rate}Hz, ${audio_channels} channels"
    else
        record_test "Audio Reception" "INFO" "No audio in stream"
    fi
else
    record_test "Display Status File" "FAIL" "Status file not found"
fi

# Test 5: Monitor display for 10 seconds
log_test "Test 5: Monitor display stability"
log_info "Monitoring display for 10 seconds..."

start_frames=$(parse_status_value "$(box_get_display_status $TEST_DISPLAY_ID)" "FRAMES_RECEIVED")
sleep 10
end_frames=$(parse_status_value "$(box_get_display_status $TEST_DISPLAY_ID)" "FRAMES_RECEIVED")

if [ -n "$start_frames" ] && [ -n "$end_frames" ]; then
    frames_received=$((end_frames - start_frames))
    expected_frames=$((30 * 10))  # Assuming 30fps for 10 seconds
    
    # Allow 20% variance for network streams
    min_frames=$((expected_frames * 80 / 100))
    
    if [ $frames_received -ge $min_frames ]; then
        record_test "Display Stability" "PASS" "Received $frames_received frames in 10s"
    else
        record_test "Display Stability" "FAIL" "Low frame count: $frames_received (expected ~$expected_frames)"
    fi
else
    record_test "Display Stability" "FAIL" "Could not get frame counts"
fi

# Test 6: Switch to different stream
log_test "Test 6: Switch to different stream"

# Get another stream if available
other_stream=$(box_list_ndi_streams | grep -v "$TEST_NDI_STREAM" | head -1)

if [ -n "$other_stream" ]; then
    log_info "Switching to stream: $other_stream"
    
    if box_assign_display "$other_stream" "$TEST_DISPLAY_ID"; then
        record_test "Stream Switching" "PASS"
        
        sleep 5
        new_status=$(box_get_display_status "$TEST_DISPLAY_ID")
        new_stream=$(parse_status_value "$new_status" "STREAM_NAME")
        
        if [ "$new_stream" = "$other_stream" ]; then
            record_test "Stream Switch Verification" "PASS" "Now showing: $new_stream"
        else
            record_test "Stream Switch Verification" "FAIL" "Stream mismatch after switch"
        fi
        
        # Switch back to original
        log_info "Switching back to original stream..."
        box_assign_display "$TEST_NDI_STREAM" "$TEST_DISPLAY_ID"
        sleep 3
    else
        record_test "Stream Switching" "FAIL" "Could not switch stream"
    fi
else
    log_info "No other streams available for switching test"
    record_test "Stream Switching" "SKIP" "Only one stream available"
fi

# Test 7: Remove stream from display
log_test "Test 7: Remove stream from display"

box_remove_display "$TEST_DISPLAY_ID"
sleep 2

if assert_service_inactive "ndi-display@${TEST_DISPLAY_ID}"; then
    record_test "Stream Removal" "PASS"
else
    record_test "Stream Removal" "FAIL" "Display service still active"
fi

# Test 8: Test with stream without audio
if [ -n "$TEST_NDI_STREAM_NO_AUDIO" ]; then
    log_test "Test 8: Stream without audio"
    
    if box_assign_display "$TEST_NDI_STREAM_NO_AUDIO" "$TEST_DISPLAY_ID"; then
        record_test "No-Audio Stream Assignment" "PASS"
        
        sleep 5
        status=$(box_get_display_status "$TEST_DISPLAY_ID")
        
        if assert_display_has_video "$TEST_DISPLAY_ID"; then
            record_test "No-Audio Stream Video" "PASS"
        else
            record_test "No-Audio Stream Video" "FAIL" "No video from stream"
        fi
        
        if assert_display_no_audio "$TEST_DISPLAY_ID"; then
            record_test "No-Audio Stream Audio Check" "PASS" "Correctly shows no audio"
        else
            record_test "No-Audio Stream Audio Check" "FAIL" "Incorrectly reports audio"
        fi
        
        # Clean up
        box_remove_display "$TEST_DISPLAY_ID"
    else
        record_test "No-Audio Stream Assignment" "FAIL"
    fi
else
    log_info "No audio-less stream configured for testing"
fi

# Test 9: Service restart with active display
log_test "Test 9: Service restart with active display"

# Assign stream again
box_assign_display "$TEST_NDI_STREAM" "$TEST_DISPLAY_ID"
sleep 3

# Restart the display service
log_info "Restarting display service..."
box_restart_service "ndi-display@${TEST_DISPLAY_ID}"
sleep 5

if assert_service_active "ndi-display@${TEST_DISPLAY_ID}"; then
    record_test "Display Service Restart" "PASS"
    
    # Check if it reconnected to the stream
    status=$(box_get_display_status "$TEST_DISPLAY_ID")
    stream=$(parse_status_value "$status" "STREAM_NAME")
    
    if [ "$stream" = "$TEST_NDI_STREAM" ]; then
        record_test "Stream Persistence" "PASS" "Stream reconnected after restart"
    else
        record_test "Stream Persistence" "FAIL" "Stream not reconnected"
    fi
else
    record_test "Display Service Restart" "FAIL" "Service did not restart"
fi

# Test 10: Multiple displays (if supported)
log_test "Test 10: Multiple displays"

# Try to start display 2
if box_assign_display "$TEST_NDI_STREAM" "2"; then
    record_test "Multiple Displays" "PASS" "Display 2 started"
    
    # Check both are active
    if assert_service_active "ndi-display@1" && assert_service_active "ndi-display@2"; then
        record_test "Concurrent Displays" "PASS" "Both displays active"
    else
        record_test "Concurrent Displays" "FAIL" "Not all displays active"
    fi
    
    # Clean up display 2
    box_remove_display "2"
else
    record_test "Multiple Displays" "INFO" "Multiple displays not supported or configured"
fi

# Clean up
log_info "Cleaning up test displays..."
box_remove_display "$TEST_DISPLAY_ID"

# Collect diagnostic logs
log_info "Collecting diagnostic information..."
display_logs=$(box_get_logs "ndi-display@${TEST_DISPLAY_ID}" 30)
log_output "NDI Display Logs" "$display_logs"

# Check for ALSA errors if audio was tested
alsa_errors=$(box_ssh "journalctl -u ndi-display@${TEST_DISPLAY_ID} | grep -i alsa | tail -10")
if [ -n "$alsa_errors" ]; then
    log_output "ALSA Messages" "$alsa_errors"
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