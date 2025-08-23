#!/bin/bash
# Assertion functions for tests

# Assert two values are equal
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"
    
    if [ "$expected" = "$actual" ]; then
        return 0
    else
        log_error "Assertion failed: $message"
        log_error "  Expected: '$expected'"
        log_error "  Actual:   '$actual'"
        return 1
    fi
}

# Assert string contains substring
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        log_error "Assertion failed: $message"
        log_error "  String: '$haystack'"
        log_error "  Should contain: '$needle'"
        return 1
    fi
}

# Assert service is active
assert_service_active() {
    local service="$1"
    local status=$(box_service_status "$service")
    
    if [ "$status" = "active" ]; then
        return 0
    else
        log_error "Service $service is not active (status: $status)"
        return 1
    fi
}

# Assert service is inactive
assert_service_inactive() {
    local service="$1"
    local status=$(box_service_status "$service")
    
    if [ "$status" = "inactive" ] || [ "$status" = "failed" ]; then
        return 0
    else
        log_error "Service $service is not inactive (status: $status)"
        return 1
    fi
}

# Assert file exists on box
assert_file_exists() {
    local file="$1"
    local result=$(box_ssh "[ -f '$file' ] && echo 'exists' || echo 'missing'")
    
    if [ "$result" = "exists" ]; then
        return 0
    else
        log_error "File $file does not exist on box"
        return 1
    fi
}

# Assert directory exists on box
assert_dir_exists() {
    local dir="$1"
    local result=$(box_ssh "[ -d '$dir' ] && echo 'exists' || echo 'missing'")
    
    if [ "$result" = "exists" ]; then
        return 0
    else
        log_error "Directory $dir does not exist on box"
        return 1
    fi
}

# Assert value is within range
assert_in_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    local message="${4:-Value should be in range}"
    
    # Handle empty or non-numeric values
    if [ -z "$value" ] || ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_error "Assertion failed: $message"
        log_error "  Value '$value' is not a valid number"
        return 1
    fi
    
    # Remove decimal points for integer comparison
    value_int=$(echo "$value" | cut -d'.' -f1)
    
    if [ "$value_int" -ge "$min" ] && [ "$value_int" -le "$max" ]; then
        return 0
    else
        log_error "Assertion failed: $message"
        log_error "  Value $value is not in range [$min, $max]"
        return 1
    fi
}

# Assert process is running
assert_process_running() {
    local process="$1"
    local status=$(box_process_running "$process")
    
    if [ "$status" = "running" ]; then
        return 0
    else
        log_error "Process '$process' is not running"
        return 1
    fi
}

# Assert capture is working
assert_capture_active() {
    local status_file=$(box_get_capture_status)
    local state=$(parse_status_value "$status_file" "CAPTURE_STATE")
    
    if [ "$state" = "ACTIVE" ] || [ "$state" = "STARTING" ] || [ "$state" = "CAPTURING" ]; then
        return 0
    else
        log_error "Capture is not active (state: $state)"
        return 1
    fi
}

# Assert FPS is within expected range
assert_fps_in_range() {
    local fps="$1"
    local expected="${2:-$EXPECTED_FPS}"
    local tolerance="${3:-$EXPECTED_FPS_TOLERANCE}"
    
    local min=$((expected - tolerance))
    local max=$((expected + tolerance))
    
    assert_in_range "$fps" "$min" "$max" "FPS should be around $expected"
}

# Assert display has video
assert_display_has_video() {
    local display_id="${1:-1}"
    local status=$(box_get_display_status "$display_id")
    
    if [ -z "$status" ]; then
        log_error "Display $display_id has no status file"
        return 1
    fi
    
    local resolution=$(parse_status_value "$status" "RESOLUTION")
    if [ -n "$resolution" ] && [ "$resolution" != "0x0" ]; then
        return 0
    else
        log_error "Display $display_id has no video (resolution: $resolution)"
        return 1
    fi
}

# Assert display has audio
assert_display_has_audio() {
    local display_id="${1:-1}"
    local status=$(box_get_display_status "$display_id")
    
    local audio_channels=$(parse_status_value "$status" "AUDIO_CHANNELS")
    if [ -n "$audio_channels" ] && [ "$audio_channels" != "0" ]; then
        return 0
    else
        log_error "Display $display_id has no audio"
        return 1
    fi
}

# Assert display has no audio
assert_display_no_audio() {
    local display_id="${1:-1}"
    local status=$(box_get_display_status "$display_id")
    
    local audio_channels=$(parse_status_value "$status" "AUDIO_CHANNELS")
    if [ -z "$audio_channels" ] || [ "$audio_channels" = "0" ]; then
        return 0
    else
        log_error "Display $display_id has audio when it shouldn't (channels: $audio_channels)"
        return 1
    fi
}

# Assert NDI stream is available
assert_ndi_stream_available() {
    local stream_name="$1"
    local streams=$(box_ssh "/opt/ndi-bridge/ndi-display list 2>/dev/null | grep -F '$stream_name'")
    
    if [ -n "$streams" ]; then
        return 0
    else
        log_error "NDI stream '$stream_name' is not available"
        return 1
    fi
}

# Assert command succeeds
assert_command_success() {
    local cmd="$1"
    local message="${2:-Command should succeed}"
    
    if box_ssh "$cmd"; then
        return 0
    else
        log_error "Assertion failed: $message"
        log_error "  Command failed: $cmd"
        return 1
    fi
}

# Assert command fails
assert_command_fails() {
    local cmd="$1"
    local message="${2:-Command should fail}"
    
    if ! box_ssh "$cmd"; then
        return 0
    else
        log_error "Assertion failed: $message"
        log_error "  Command succeeded when it should have failed: $cmd"
        return 1
    fi
}

# Assert time synchronization
assert_time_synchronized() {
    local sync_status=$(box_get_time_sync_status | grep "TIME_SYNC:" | cut -d: -f2 | xargs)
    
    if [ "$sync_status" = "PTP (Primary)" ]; then
        log_info "Time synchronized via PTP (best)"
        return 0
    elif [ "$sync_status" = "NTP (Fallback)" ]; then
        log_info "Time synchronized via NTP (fallback)"
        return 0
    else
        log_error "Time not synchronized (status: $sync_status)"
        return 1
    fi
}

# Assert PTP is working
assert_ptp_active() {
    local ptp_state=$(box_check_ptp_sync)
    
    if [ "$ptp_state" = "PTP_SYNCHRONIZED" ]; then
        return 0
    else
        log_error "PTP not synchronized (state: $ptp_state)"
        return 1
    fi
}