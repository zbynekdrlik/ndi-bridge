#!/bin/bash
# Audio functionality test suite
# Tests NDI audio output to HDMI and audio-less streams

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Audio Test Suite"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"
log_info "Audio stream: $TEST_NDI_STREAM"
log_info "No-audio stream: $TEST_NDI_STREAM_NO_AUDIO"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Test 1: Check ALSA devices
log_test "Test 1: ALSA device detection"

alsa_devices=$(box_ssh "aplay -l 2>/dev/null | grep '^card'")
if [ -n "$alsa_devices" ]; then
    record_test "ALSA Device Detection" "PASS"
    log_info "ALSA devices found:"
    echo "$alsa_devices"
    
    # Check for HDMI audio devices
    hdmi_devices=$(echo "$alsa_devices" | grep -i hdmi | wc -l)
    if [ $hdmi_devices -gt 0 ]; then
        record_test "HDMI Audio Devices" "PASS" "Found $hdmi_devices HDMI audio devices"
    else
        record_test "HDMI Audio Devices" "FAIL" "No HDMI audio devices found"
    fi
else
    record_test "ALSA Device Detection" "FAIL" "No ALSA devices found"
    log_error "Cannot continue without ALSA devices"
    print_test_summary
    exit 1
fi

# Test 2: Test ALSA output with speaker-test
log_test "Test 2: ALSA output test"

# Test primary HDMI output (Display 1 -> hw:2,3)
log_info "Testing ALSA device hw:2,3 (Display 1)..."
if box_ssh "timeout 2 speaker-test -D hw:2,3 -c 2 -t sine -f 440 > /dev/null 2>&1"; then
    record_test "ALSA Output hw:2,3" "PASS"
else
    record_test "ALSA Output hw:2,3" "WARN" "Device may not be connected or active"
fi

# Test 3: Test with real CG NDI stream with audio
log_test "Test 3: CG NDI stream with audio"

# Stop any existing display
box_stop_service "ndi-display@${TEST_DISPLAY_ID}" 2>/dev/null || true
sleep 2

# Try to find a real CG NDI stream with audio (not USB Capture which has no audio)
log_info "Looking for CG NDI streams with audio..."
available_streams=$(box_ssh "/opt/ndi-bridge/ndi-display list 2>/dev/null | grep -E 'RESOLUME|CG|cg-obs|Arena' || echo ''")

# Check if we have CG streams available (RESOLUME streams have audio)
if echo "$available_streams" | grep -q "RESOLUME"; then
    # Use RESOLUME CG stream which has audio
    CG_STREAM="RESOLUME-SNV (cg-obs)"
    log_info "Using CG stream with audio: $CG_STREAM"
    TEST_AUDIO_STREAM="$CG_STREAM"
elif echo "$available_streams" | grep -q "Arena"; then
    # Alternative CG stream
    CG_STREAM="RESOLUME-SNV (Arena - VJ)"
    log_info "Using CG stream with audio: $CG_STREAM"
    TEST_AUDIO_STREAM="$CG_STREAM"
else
    log_warn "No CG streams found, using default test stream (no audio)"
    TEST_AUDIO_STREAM="$TEST_NDI_STREAM"
fi

# Assign stream with audio
if box_assign_display "$TEST_AUDIO_STREAM" "$TEST_DISPLAY_ID"; then
    record_test "Audio Stream Assignment" "PASS"
    
    sleep 5  # Give time for audio to start
    
    # Check display status
    display_status=$(box_get_display_status "$TEST_DISPLAY_ID")
    
    if assert_display_has_video "$TEST_DISPLAY_ID"; then
        record_test "Audio Stream Video" "PASS"
    else
        record_test "Audio Stream Video" "FAIL" "No video from audio stream"
    fi
    
    if assert_display_has_audio "$TEST_DISPLAY_ID"; then
        record_test "Audio Stream Audio Detection" "PASS"
        
        # Get audio details
        audio_channels=$(parse_status_value "$display_status" "AUDIO_CHANNELS")
        audio_rate=$(parse_status_value "$display_status" "AUDIO_SAMPLE_RATE")
        audio_frames=$(parse_status_value "$display_status" "AUDIO_FRAMES")
        
        log_info "Audio format: ${audio_rate}Hz, ${audio_channels} channels"
        log_info "Audio frames received: $audio_frames"
        
        # Verify audio format
        if [ "$audio_rate" = "$EXPECTED_AUDIO_RATE" ]; then
            record_test "Audio Sample Rate" "PASS" "Rate: ${audio_rate}Hz"
        else
            record_test "Audio Sample Rate" "WARN" "Rate: ${audio_rate}Hz (expected ${EXPECTED_AUDIO_RATE}Hz)"
        fi
        
        if [ "$audio_channels" = "$EXPECTED_AUDIO_CHANNELS" ]; then
            record_test "Audio Channels" "PASS" "Channels: $audio_channels"
        else
            record_test "Audio Channels" "WARN" "Channels: $audio_channels (expected $EXPECTED_AUDIO_CHANNELS)"
        fi
        
        # Monitor audio frame count
        sleep 5
        new_audio_frames=$(parse_status_value "$(box_get_display_status $TEST_DISPLAY_ID)" "AUDIO_FRAMES")
        
        if [ -n "$audio_frames" ] && [ -n "$new_audio_frames" ]; then
            audio_processed=$((new_audio_frames - audio_frames))
            if [ $audio_processed -gt 0 ]; then
                record_test "Audio Processing" "PASS" "Processed $audio_processed audio frames in 5s"
            else
                record_test "Audio Processing" "FAIL" "No audio frames processed"
            fi
        fi
    else
        record_test "Audio Stream Audio Detection" "FAIL" "No audio detected from stream"
    fi
else
    record_test "Audio Stream Assignment" "FAIL" "Could not assign audio stream"
fi

# Test 4: Check ALSA process
log_test "Test 4: ALSA process verification"

# Check if ndi-display is using ALSA
alsa_usage=$(box_ssh "lsof 2>/dev/null | grep ndi-display | grep -E 'snd|pcm' | head -5")
if [ -n "$alsa_usage" ]; then
    record_test "ALSA Usage" "PASS" "ndi-display is using ALSA devices"
    log_output "ALSA File Descriptors" "$alsa_usage"
else
    record_test "ALSA Usage" "WARN" "Could not verify ALSA usage"
fi

# Test 5: Stream without audio
log_test "Test 5: Stream without audio"

if [ -n "$TEST_NDI_STREAM_NO_AUDIO" ]; then
    log_info "Testing stream without audio: $TEST_NDI_STREAM_NO_AUDIO"
    
    # Switch to no-audio stream
    if box_assign_display "$TEST_NDI_STREAM_NO_AUDIO" "$TEST_DISPLAY_ID"; then
        record_test "No-Audio Stream Assignment" "PASS"
        
        sleep 5
        
        # Verify no audio
        if assert_display_no_audio "$TEST_DISPLAY_ID"; then
            record_test "No-Audio Verification" "PASS" "Correctly handles stream without audio"
        else
            record_test "No-Audio Verification" "FAIL" "Incorrectly reports audio for no-audio stream"
        fi
        
        # Check that video still works
        if assert_display_has_video "$TEST_DISPLAY_ID"; then
            record_test "No-Audio Stream Video" "PASS" "Video works without audio"
        else
            record_test "No-Audio Stream Video" "FAIL" "Video failed on no-audio stream"
        fi
        
        # Check service stability
        if assert_service_active "ndi-display@${TEST_DISPLAY_ID}"; then
            record_test "No-Audio Service Stability" "PASS" "Service stable without audio"
        else
            record_test "No-Audio Service Stability" "FAIL" "Service crashed without audio"
        fi
    else
        record_test "No-Audio Stream Assignment" "FAIL" "Could not assign no-audio stream"
    fi
else
    log_warn "No audio-less stream configured, skipping no-audio tests"
    record_test "No-Audio Stream Test" "SKIP" "TEST_NDI_STREAM_NO_AUDIO not configured"
fi

# Test 6: Audio continuity during stream switch
log_test "Test 6: Audio continuity during stream switch"

# Get list of streams with audio
audio_streams=$(box_list_ndi_streams | head -3)
stream_count=$(echo "$audio_streams" | wc -l)

if [ $stream_count -ge 2 ]; then
    log_info "Testing audio continuity with stream switching..."
    
    first_stream=$(echo "$audio_streams" | head -1)
    second_stream=$(echo "$audio_streams" | head -2 | tail -1)
    
    # Start with first stream
    box_assign_display "$first_stream" "$TEST_DISPLAY_ID"
    sleep 3
    
    # Switch to second stream
    log_info "Switching from '$first_stream' to '$second_stream'..."
    box_assign_display "$second_stream" "$TEST_DISPLAY_ID"
    sleep 3
    
    # Check if audio is still working
    if assert_service_active "ndi-display@${TEST_DISPLAY_ID}"; then
        status=$(box_get_display_status "$TEST_DISPLAY_ID")
        audio_channels=$(parse_status_value "$status" "AUDIO_CHANNELS")
        
        if [ -n "$audio_channels" ] && [ "$audio_channels" != "0" ]; then
            record_test "Audio Stream Switching" "PASS" "Audio maintained during switch"
        else
            record_test "Audio Stream Switching" "WARN" "Audio state after switch: $audio_channels channels"
        fi
    else
        record_test "Audio Stream Switching" "FAIL" "Service failed during switch"
    fi
else
    log_info "Not enough streams for switching test"
    record_test "Audio Stream Switching" "SKIP" "Need at least 2 streams"
fi

# Test 7: Audio performance monitoring
log_test "Test 7: Audio performance monitoring"

# Switch back to main test stream
box_assign_display "$TEST_NDI_STREAM" "$TEST_DISPLAY_ID"
sleep 5

if assert_display_has_audio "$TEST_DISPLAY_ID"; then
    log_info "Monitoring audio performance for 10 seconds..."
    
    start_frames=$(parse_status_value "$(box_get_display_status $TEST_DISPLAY_ID)" "AUDIO_FRAMES")
    start_time=$(date +%s)
    
    sleep 10
    
    end_frames=$(parse_status_value "$(box_get_display_status $TEST_DISPLAY_ID)" "AUDIO_FRAMES")
    end_time=$(date +%s)
    
    if [ -n "$start_frames" ] && [ -n "$end_frames" ]; then
        frames_processed=$((end_frames - start_frames))
        duration=$((end_time - start_time))
        
        # Calculate expected frames (48000Hz, stereo, typical NDI frame size ~1920 samples)
        # NDI typically sends ~25-50 audio frames per second
        expected_min=$((duration * 20))  # Minimum 20 audio frames/sec
        expected_max=$((duration * 60))  # Maximum 60 audio frames/sec
        
        if [ $frames_processed -ge $expected_min ] && [ $frames_processed -le $expected_max ]; then
            frames_per_sec=$((frames_processed / duration))
            record_test "Audio Performance" "PASS" "Processing ~$frames_per_sec audio frames/sec"
        else
            record_test "Audio Performance" "WARN" "Processed $frames_processed frames in ${duration}s"
        fi
    else
        record_test "Audio Performance" "FAIL" "Could not measure audio performance"
    fi
else
    record_test "Audio Performance" "SKIP" "No audio to monitor"
fi

# Test 8: Check for ALSA errors
log_test "Test 8: ALSA error check"

alsa_errors=$(box_ssh "journalctl -u ndi-display@${TEST_DISPLAY_ID} -n 100 | grep -iE 'alsa|audio|snd' | grep -iE 'error|fail|unable' | tail -10")

if [ -z "$alsa_errors" ]; then
    record_test "ALSA Errors" "PASS" "No ALSA errors detected"
else
    record_test "ALSA Errors" "WARN" "ALSA errors found in logs"
    log_output "ALSA Errors" "$alsa_errors"
fi

# Test 9: Audio recovery after service restart
log_test "Test 9: Audio recovery after service restart"

log_info "Restarting display service..."
box_restart_service "ndi-display@${TEST_DISPLAY_ID}"
sleep 5

if assert_service_active "ndi-display@${TEST_DISPLAY_ID}"; then
    # Check if audio recovered
    if assert_display_has_audio "$TEST_DISPLAY_ID"; then
        record_test "Audio Recovery" "PASS" "Audio recovered after service restart"
    else
        record_test "Audio Recovery" "FAIL" "Audio did not recover after restart"
    fi
else
    record_test "Audio Recovery" "FAIL" "Service did not restart"
fi

# Clean up
log_info "Cleaning up audio tests..."
box_remove_display "$TEST_DISPLAY_ID"

# Collect diagnostic information
log_info "Collecting audio diagnostic information..."

# Get ALSA configuration
alsa_config=$(box_ssh "cat /proc/asound/cards 2>/dev/null")
if [ -n "$alsa_config" ]; then
    log_output "ALSA Cards" "$alsa_config"
fi

# Get display service logs focusing on audio
audio_logs=$(box_ssh "journalctl -u ndi-display@${TEST_DISPLAY_ID} -n 50 | grep -iE 'audio|alsa|pcm|snd'")
if [ -n "$audio_logs" ]; then
    log_output "Audio-related Logs" "$audio_logs"
fi

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All audio tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED audio tests failed"
    exit 1
fi