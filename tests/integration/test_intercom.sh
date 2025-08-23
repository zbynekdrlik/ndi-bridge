#!/bin/bash

# Source test libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"

test_intercom_dependencies() {
    start_test "Intercom Dependencies"
    
    # Check if chromium is installed
    assert_command_exists "chromium-browser" \
        "Chromium browser should be installed" || \
    assert_command_exists "chromium" \
        "Chromium should be installed (alternate name)"
    
    # Check for audio utilities
    assert_command_exists "arecord" \
        "ALSA record utility should be installed"
    
    assert_command_exists "aplay" \
        "ALSA play utility should be installed"
    
    end_test
}

test_intercom_files() {
    start_test "Intercom Files"
    
    # Check if service file exists
    assert_file_exists "/etc/systemd/system/ndi-bridge-intercom.service" \
        "Intercom service file should exist"
    
    # Check if intercom script exists and is executable
    assert_file_exists "/opt/ndi-bridge/ndi-bridge-intercom" \
        "Intercom script should exist"
    
    assert_executable "/opt/ndi-bridge/ndi-bridge-intercom" \
        "Intercom script should be executable"
    
    # Check config file
    assert_file_exists "/etc/ndi-bridge/intercom.conf" \
        "Intercom config file should exist"
    
    end_test
}

test_intercom_config() {
    start_test "Intercom Configuration"
    
    # Check config file exists
    assert_file_exists "/etc/ndi-bridge/intercom.conf" \
        "Intercom config file should exist"
    
    # Source and verify config values
    if [ -f "/etc/ndi-bridge/intercom.conf" ]; then
        source /etc/ndi-bridge/intercom.conf
        
        assert_equals "$INTERCOM_ENABLED" "true" \
            "Intercom should be enabled by default"
        
        assert_equals "$VDO_ROOM" "nl_interkom" \
            "Room should be nl_interkom"
        
        assert_not_empty "$VDO_SERVER" \
            "VDO server URL should be set"
        
        assert_not_empty "$AUDIO_DEVICE" \
            "Audio device should be configured"
    fi
    
    end_test
}

test_intercom_audio_device() {
    start_test "Intercom Audio Device"
    
    # Check for audio capture devices
    run_command "arecord -l 2>/dev/null | grep -q 'card'" \
        "Audio capture device should be available"
    
    # Check for audio playback devices
    run_command "aplay -l 2>/dev/null | grep -q 'card'" \
        "Audio playback device should be available"
    
    # Check default audio device
    run_command "arecord -L 2>/dev/null | grep -q 'default'" \
        "Default audio device should be configured"
    
    # Test if we can access the audio device (non-destructive)
    run_command "timeout 1 arecord -d 0.1 -f cd -t raw /dev/null 2>/dev/null" \
        "Should be able to access audio capture device" || true
    
    end_test
}

test_intercom_service() {
    start_test "Intercom Service"
    
    # Check if service is enabled
    run_command "systemctl is-enabled ndi-bridge-intercom 2>/dev/null | grep -E 'enabled|linked'" \
        "Intercom service should be enabled" || true
    
    # Start the service if not running
    if ! systemctl is-active --quiet ndi-bridge-intercom 2>/dev/null; then
        run_command "systemctl start ndi-bridge-intercom" \
            "Should be able to start intercom service"
        sleep 5
    fi
    
    # Check if service is running
    assert_service_running "ndi-bridge-intercom" \
        "Intercom service should be running"
    
    # Check for chromium process
    assert_process_running "chromium.*intercom\|chromium.*vdo.ninja" \
        "Chromium should be running with intercom or VDO.Ninja"
    
    # Check service logs for errors
    run_command "! journalctl -u ndi-bridge-intercom -n 50 --no-pager 2>/dev/null | grep -i 'error\|fatal\|failed' | grep -v 'No errors'" \
        "No critical errors in intercom logs" || true
    
    end_test
}

test_intercom_resource_usage() {
    start_test "Intercom Resource Usage"
    
    # Get intercom process PID
    INTERCOM_PID=$(pgrep -f "vdo.ninja.*interkom" 2>/dev/null | head -1)
    if [ -z "$INTERCOM_PID" ]; then
        INTERCOM_PID=$(pgrep -f "chromium.*intercom" 2>/dev/null | head -1)
    fi
    
    if [ -n "$INTERCOM_PID" ]; then
        # Check memory usage
        MEM_KB=$(ps -o rss= -p $INTERCOM_PID 2>/dev/null | tr -d ' ')
        if [ -n "$MEM_KB" ]; then
            MEM_MB=$((MEM_KB / 1024))
            assert_less_than "$MEM_MB" "600" \
                "Intercom memory usage should be less than 600MB (currently ${MEM_MB}MB)"
        fi
        
        # Check CPU usage
        CPU_USAGE=$(ps -o %cpu= -p $INTERCOM_PID 2>/dev/null | tr -d ' ' | cut -d. -f1)
        if [ -n "$CPU_USAGE" ]; then
            assert_less_than "$CPU_USAGE" "25" \
                "Intercom CPU usage should be less than 25% (currently ${CPU_USAGE}%)" || true
        fi
    else
        log_warning "Intercom process not found for resource check"
    fi
    
    end_test
}

test_intercom_helper_scripts() {
    start_test "Intercom Helper Scripts"
    
    # Check for helper scripts
    assert_file_exists "/opt/ndi-bridge/ndi-bridge-intercom-status" \
        "Intercom status script should exist" || true
    
    assert_file_exists "/opt/ndi-bridge/ndi-bridge-intercom-logs" \
        "Intercom logs script should exist" || true
    
    assert_file_exists "/opt/ndi-bridge/ndi-bridge-intercom-restart" \
        "Intercom restart script should exist" || true
    
    # Test if scripts are executable
    if [ -f "/opt/ndi-bridge/ndi-bridge-intercom-status" ]; then
        assert_executable "/opt/ndi-bridge/ndi-bridge-intercom-status" \
            "Status script should be executable"
    fi
    
    end_test
}

test_intercom_welcome_integration() {
    start_test "Intercom Welcome Screen Integration"
    
    # Check if welcome screen shows intercom status
    if [ -x "/opt/ndi-bridge/ndi-bridge-welcome" ]; then
        run_command "/opt/ndi-bridge/ndi-bridge-welcome 2>/dev/null | grep -q 'INTERCOM STATUS'" \
            "Welcome screen should show intercom section"
        
        # Check if status is displayed
        WELCOME_OUTPUT=$(/opt/ndi-bridge/ndi-bridge-welcome 2>/dev/null)
        if echo "$WELCOME_OUTPUT" | grep -q "INTERCOM STATUS"; then
            log_success "Intercom section found in welcome screen"
            
            # Check for status indicator
            if echo "$WELCOME_OUTPUT" | grep -q "Status:.*Connected\|Status:.*Stopped\|Status:.*Failed"; then
                log_success "Intercom status indicator working"
            else
                log_warning "Intercom status indicator not showing expected values"
            fi
        fi
    else
        log_warning "Welcome screen not found for integration test"
    fi
    
    end_test
}

test_intercom_connectivity() {
    start_test "Intercom Connectivity"
    
    # Check if we can resolve VDO.Ninja domain
    run_command "nslookup vdo.ninja >/dev/null 2>&1 || host vdo.ninja >/dev/null 2>&1" \
        "Should be able to resolve vdo.ninja domain"
    
    # Check if chromium can access the URL (dry run)
    if which chromium-browser >/dev/null 2>&1; then
        run_command "timeout 5 chromium-browser --headless --dump-dom 'https://vdo.ninja' 2>/dev/null | grep -q '</html>'" \
            "Chromium should be able to access VDO.Ninja" || true
    fi
    
    end_test
}

# Run all tests
run_test_suite "Intercom Tests" \
    test_intercom_dependencies \
    test_intercom_files \
    test_intercom_config \
    test_intercom_audio_device \
    test_intercom_service \
    test_intercom_resource_usage \
    test_intercom_helper_scripts \
    test_intercom_welcome_integration \
    test_intercom_connectivity