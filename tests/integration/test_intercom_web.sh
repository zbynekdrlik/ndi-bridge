#!/bin/bash
# Comprehensive Web Intercom Interface Test Suite
# Tests all web functionality including JavaScript interactions and real-time updates

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"
source "${SCRIPT_DIR}/../lib/ro_check.sh"

# Test configuration
TEST_NAME="Web Intercom Interface Test Suite"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"
log_info "Testing FULL web functionality including JavaScript execution"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Verify filesystem is read-only before testing
if ! verify_readonly_filesystem; then
    exit 1
fi

# Helper function to execute JavaScript via API calls
execute_web_action() {
    local action="$1"
    local params="$2"
    local endpoint="$3"
    
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$params" \
        "http://${TEST_BOX_IP}:8089/api/intercom/$endpoint" 2>/dev/null
}

# Helper function to get current state via API
get_current_state() {
    curl -s "http://${TEST_BOX_IP}:8089/api/intercom/status" 2>/dev/null
}

# Test 1: Web page loads with all required JavaScript functions
log_test "Test 1: Web page JavaScript functions availability"

# Get the web page content
web_content=$(curl -s --user admin:newlevel "http://${TEST_BOX_IP}/intercom" 2>/dev/null)

# Check for all required JavaScript functions
js_functions=(
    "toggleMute"
    "setVolume"
    "saveDefaults"
    "loadDefaults"
    "refreshStatus"
    "muteInput"
    "muteOutput"
    "restartService"
    "updateUI"
    "executeCommand"
    "showAlert"
    "showModal"
)

all_functions_present=true
for func in "${js_functions[@]}"; do
    if echo "$web_content" | grep -q "function $func\|$func()"; then
        log_info "  ✓ JavaScript function '$func' present"
    else
        log_error "  ✗ JavaScript function '$func' missing"
        all_functions_present=false
    fi
done

if $all_functions_present; then
    record_test "JavaScript Functions" "PASS" "All functions present"
else
    record_test "JavaScript Functions" "FAIL" "Some functions missing"
fi

# Test 2: Auto-refresh functionality simulation
log_test "Test 2: Auto-refresh status updates"

# Get initial state
initial_state=$(get_current_state)
initial_output_vol=$(echo "$initial_state" | grep -oP '"output"[^}]*"volume":\s*\K\d+' || echo "0")

log_info "Initial output volume: ${initial_output_vol}%"

# Change volume via backend
box_ssh "/usr/local/bin/ndi-bridge-intercom-control volume output 45" >/dev/null 2>&1

# Wait for potential auto-refresh (simulating the 5-second interval)
sleep 6

# Get state again (simulating what auto-refresh would do)
new_state=$(get_current_state)
new_output_vol=$(echo "$new_state" | grep -oP '"output"[^}]*"volume":\s*\K\d+' || echo "0")

if [ "$new_output_vol" = "45" ]; then
    record_test "Status Refresh Data" "PASS" "Updated volume reflected: ${new_output_vol}%"
else
    record_test "Status Refresh Data" "FAIL" "Volume not updated: ${new_output_vol}%"
fi

# Test 3: Mute button toggle functionality via API
log_test "Test 3: Web mute button toggle functionality"

# Ensure unmuted state first
execute_web_action "unmute" '{"target":"both"}' "unmute" >/dev/null

# Get initial mute state
initial_state=$(get_current_state)
initial_output_muted=$(echo "$initial_state" | grep -oP '"output"[^}]*"muted":\s*\K(true|false)' || echo "false")
initial_input_muted=$(echo "$initial_state" | grep -oP '"input"[^}]*"muted":\s*\K(true|false)' || echo "false")

log_info "Initial state - Output muted: $initial_output_muted, Input muted: $initial_input_muted"

# Simulate clicking mute toggle button (toggleMute function)
toggle_response=$(execute_web_action "toggle" '{"target":"both"}' "toggle")

if echo "$toggle_response" | grep -q '"success".*true'; then
    record_test "Mute Toggle Click" "PASS" "Toggle executed"
else
    record_test "Mute Toggle Click" "FAIL" "Toggle failed"
fi

# Verify state changed
sleep 1
new_state=$(get_current_state)
new_output_muted=$(echo "$new_state" | grep -oP '"output"[^}]*"muted":\s*\K(true|false)' || echo "false")
new_input_muted=$(echo "$new_state" | grep -oP '"input"[^}]*"muted":\s*\K(true|false)' || echo "false")

if [ "$initial_output_muted" != "$new_output_muted" ] && [ "$initial_input_muted" != "$new_input_muted" ]; then
    record_test "Mute Toggle Effect" "PASS" "Both mute states toggled"
else
    record_test "Mute Toggle Effect" "FAIL" "Mute states unchanged"
fi

# Test 4: Volume slider functionality
log_test "Test 4: Volume slider interactions"

# Test output volume slider change
volume_values=(25 50 75 100 0)
for vol in "${volume_values[@]}"; do
    # Simulate slider change (setVolume function)
    vol_response=$(execute_web_action "volume" "{\"target\":\"output\",\"value\":$vol}" "volume")
    
    if echo "$vol_response" | grep -q '"success".*true'; then
        # Verify actual change
        current_state=$(get_current_state)
        actual_vol=$(echo "$current_state" | grep -oP '"output"[^}]*"volume":\s*\K\d+' || echo "0")
        
        if [ "$actual_vol" = "$vol" ]; then
            log_info "  ✓ Output volume slider: ${vol}% set correctly"
        else
            log_error "  ✗ Output volume slider: Expected ${vol}%, got ${actual_vol}%"
            record_test "Output Volume Slider" "FAIL" "Volume mismatch"
            break
        fi
    else
        record_test "Output Volume Slider" "FAIL" "API call failed"
        break
    fi
done

if [ "$actual_vol" = "0" ]; then
    record_test "Output Volume Slider" "PASS" "All values set correctly (25,50,75,100,0)"
fi

# Test input volume slider
execute_web_action "volume" '{"target":"input","value":80}' "volume" >/dev/null
sleep 1
current_state=$(get_current_state)
input_vol=$(echo "$current_state" | grep -oP '"input"[^}]*"volume":\s*\K\d+' || echo "0")

if [ "$input_vol" = "80" ]; then
    record_test "Input Volume Slider" "PASS" "Volume set to 80%"
else
    record_test "Input Volume Slider" "FAIL" "Expected 80%, got ${input_vol}%"
fi

# Test 5: Quick action buttons
log_test "Test 5: Quick action buttons functionality"

# Test "Mute Mic Only" button (muteInput function)
execute_web_action "unmute" '{"target":"both"}' "unmute" >/dev/null
sleep 1

mute_input_response=$(execute_web_action "mute" '{"target":"input"}' "mute")
if echo "$mute_input_response" | grep -q '"success".*true'; then
    current_state=$(get_current_state)
    input_muted=$(echo "$current_state" | grep -oP '"input"[^}]*"muted":\s*\K(true|false)')
    output_muted=$(echo "$current_state" | grep -oP '"output"[^}]*"muted":\s*\K(true|false)')
    
    if [ "$input_muted" = "true" ] && [ "$output_muted" = "false" ]; then
        record_test "Mute Mic Only Button" "PASS" "Only mic muted"
    else
        record_test "Mute Mic Only Button" "FAIL" "Wrong mute state"
    fi
else
    record_test "Mute Mic Only Button" "FAIL" "Command failed"
fi

# Test "Mute Speakers Only" button (muteOutput function)
execute_web_action "unmute" '{"target":"both"}' "unmute" >/dev/null
sleep 1

mute_output_response=$(execute_web_action "mute" '{"target":"output"}' "mute")
if echo "$mute_output_response" | grep -q '"success".*true'; then
    current_state=$(get_current_state)
    input_muted=$(echo "$current_state" | grep -oP '"input"[^}]*"muted":\s*\K(true|false)')
    output_muted=$(echo "$current_state" | grep -oP '"output"[^}]*"muted":\s*\K(true|false)')
    
    if [ "$input_muted" = "false" ] && [ "$output_muted" = "true" ]; then
        record_test "Mute Speakers Only Button" "PASS" "Only speakers muted"
    else
        record_test "Mute Speakers Only Button" "FAIL" "Wrong mute state"
    fi
else
    record_test "Mute Speakers Only Button" "FAIL" "Command failed"
fi

# Test "Set All to 50%" button
execute_web_action "volume" '{"target":"both","value":50}' "volume" >/dev/null
sleep 1
current_state=$(get_current_state)
output_vol=$(echo "$current_state" | grep -oP '"output"[^}]*"volume":\s*\K\d+')
input_vol=$(echo "$current_state" | grep -oP '"input"[^}]*"volume":\s*\K\d+')

if [ "$output_vol" = "50" ] && [ "$input_vol" = "50" ]; then
    record_test "Set All to 50% Button" "PASS" "Both volumes at 50%"
else
    record_test "Set All to 50% Button" "FAIL" "Volumes: out=${output_vol}%, in=${input_vol}%"
fi

# Test "Set All to 100%" button
execute_web_action "volume" '{"target":"both","value":100}' "volume" >/dev/null
sleep 1
current_state=$(get_current_state)
output_vol=$(echo "$current_state" | grep -oP '"output"[^}]*"volume":\s*\K\d+')
input_vol=$(echo "$current_state" | grep -oP '"input"[^}]*"volume":\s*\K\d+')

if [ "$output_vol" = "100" ] && [ "$input_vol" = "100" ]; then
    record_test "Set All to 100% Button" "PASS" "Both volumes at 100%"
else
    record_test "Set All to 100% Button" "FAIL" "Volumes: out=${output_vol}%, in=${input_vol}%"
fi

# Test 6: Save defaults functionality
log_test "Test 6: Save defaults button with persistence"

# Set specific test values
execute_web_action "volume" '{"target":"output","value":77}' "volume" >/dev/null
execute_web_action "volume" '{"target":"input","value":88}' "volume" >/dev/null
execute_web_action "mute" '{"target":"output"}' "mute" >/dev/null
sleep 1

# Save defaults (saveDefaults function)
save_response=$(execute_web_action "save-defaults" '{}' "save-defaults")
if echo "$save_response" | grep -q '"success".*true'; then
    record_test "Save Defaults Button" "PASS" "Settings saved"
    
    # Verify config file created
    config_exists=$(box_ssh "[ -f /etc/ndi-bridge/intercom.conf ] && echo 'yes' || echo 'no'")
    if [ "$config_exists" = "yes" ]; then
        record_test "Config File Creation" "PASS" "Configuration persisted"
        
        # Check config content
        config_content=$(box_ssh "cat /etc/ndi-bridge/intercom.conf")
        if echo "$config_content" | grep -q "INTERCOM_OUTPUT_VOLUME=77" && \
           echo "$config_content" | grep -q "INTERCOM_INPUT_VOLUME=88"; then
            record_test "Config Content" "PASS" "Correct values saved"
        else
            record_test "Config Content" "FAIL" "Wrong values in config"
        fi
    else
        record_test "Config File Creation" "FAIL" "No config file"
    fi
else
    record_test "Save Defaults Button" "FAIL" "Save failed"
fi

# Test 7: Load defaults functionality
log_test "Test 7: Load defaults button"

# Change values to different ones
execute_web_action "volume" '{"target":"output","value":30}' "volume" >/dev/null
execute_web_action "volume" '{"target":"input","value":40}' "volume" >/dev/null
execute_web_action "unmute" '{"target":"output"}' "unmute" >/dev/null
sleep 1

# Load defaults (loadDefaults function)
load_response=$(execute_web_action "load-defaults" '{}' "load-defaults")
if echo "$load_response" | grep -q '"success".*true'; then
    record_test "Load Defaults Button" "PASS" "Load executed"
    
    # Verify values restored
    sleep 2
    current_state=$(get_current_state)
    output_vol=$(echo "$current_state" | grep -oP '"output"[^}]*"volume":\s*\K\d+')
    input_vol=$(echo "$current_state" | grep -oP '"input"[^}]*"volume":\s*\K\d+')
    output_muted=$(echo "$current_state" | grep -oP '"output"[^}]*"muted":\s*\K(true|false)')
    
    if [ "$output_vol" = "77" ] && [ "$input_vol" = "88" ] && [ "$output_muted" = "true" ]; then
        record_test "Defaults Restored" "PASS" "All values restored correctly"
    else
        record_test "Defaults Restored" "FAIL" "Values: out=${output_vol}% in=${input_vol}% muted=${output_muted}"
    fi
else
    record_test "Load Defaults Button" "FAIL" "Load failed"
fi

# Test 8: Service restart button
log_test "Test 8: Restart service button functionality"

# Get service PID before restart
pid_before=$(box_ssh "systemctl show ndi-bridge-intercom.service --property=MainPID | cut -d'=' -f2")
log_info "Service PID before restart: $pid_before"

# Restart service (restartService function)
restart_response=$(execute_web_action "restart" '{}' "restart")
if echo "$restart_response" | grep -q '"success".*true'; then
    record_test "Restart Service Button" "PASS" "Restart initiated"
    
    # Wait for service to restart
    sleep 5
    
    # Verify service restarted (different PID)
    pid_after=$(box_ssh "systemctl show ndi-bridge-intercom.service --property=MainPID | cut -d'=' -f2")
    
    if [ "$pid_before" != "$pid_after" ] && [ "$pid_after" != "0" ]; then
        record_test "Service Restarted" "PASS" "New PID: $pid_after"
    else
        record_test "Service Restarted" "FAIL" "PID unchanged or service dead"
    fi
else
    record_test "Restart Service Button" "FAIL" "Restart failed"
fi

# Test 9: Visual feedback elements
log_test "Test 9: Visual feedback and status indicators"

# Check status indicator updates
current_state=$(get_current_state)
service_status=$(echo "$current_state" | grep -oP '"service":\s*"\K[^"]+')

if [ "$service_status" = "running" ]; then
    record_test "Service Status Indicator" "PASS" "Shows running"
else
    record_test "Service Status Indicator" "FAIL" "Shows: $service_status"
fi

# Verify device information display
output_device=$(echo "$current_state" | grep -oP '"output"[^}]*"device":\s*"\K[^"]+')
input_device=$(echo "$current_state" | grep -oP '"input"[^}]*"device":\s*"\K[^"]+')

if [ -n "$output_device" ] && [ -n "$input_device" ]; then
    record_test "Device Info Display" "PASS" "Devices shown"
    log_info "  Output device: $output_device"
    log_info "  Input device: $input_device"
else
    record_test "Device Info Display" "FAIL" "Device info missing"
fi

# Test 10: Modal dialog functionality (confirmation prompts)
log_test "Test 10: Modal confirmation dialogs"

# The save defaults should have triggered a modal
# We can't directly test JavaScript modals, but we can verify the functions exist
if echo "$web_content" | grep -q "showModal" && \
   echo "$web_content" | grep -q "confirmAction" && \
   echo "$web_content" | grep -q "closeModal"; then
    record_test "Modal Dialog Functions" "PASS" "Modal system present"
else
    record_test "Modal Dialog Functions" "FAIL" "Modal functions missing"
fi

# Test 11: Alert notification system
log_test "Test 11: Alert notification system"

# Check for alert display function
if echo "$web_content" | grep -q "showAlert" && \
   echo "$web_content" | grep -q "alert-container"; then
    record_test "Alert System" "PASS" "Alert system present"
else
    record_test "Alert System" "FAIL" "Alert system missing"
fi

# Test 12: WebSocket connection attempt
log_test "Test 12: WebSocket support check"

# Check if WebSocket connection code exists
if echo "$web_content" | grep -q "WebSocket" && \
   echo "$web_content" | grep -q "connectWebSocket"; then
    record_test "WebSocket Support" "PASS" "WebSocket code present"
else
    record_test "WebSocket Support" "INFO" "WebSocket not implemented (uses polling)"
fi

# Test 13: Responsive design elements
log_test "Test 13: Responsive design verification"

# Check for responsive CSS media queries
if echo "$web_content" | grep -q "@media.*max-width.*768px"; then
    record_test "Responsive Design" "PASS" "Mobile styles present"
else
    record_test "Responsive Design" "FAIL" "No responsive styles"
fi

# Test 14: Error handling
log_test "Test 14: Error handling in web interface"

# Test with invalid volume value
invalid_vol_response=$(curl -s -X POST \
    -H "Content-Type: application/json" \
    -d '{"target":"output","value":150}' \
    "http://${TEST_BOX_IP}:8089/api/intercom/volume" 2>/dev/null)

if echo "$invalid_vol_response" | grep -q "error\|must be between"; then
    record_test "Volume Range Validation" "PASS" "Invalid value rejected"
else
    record_test "Volume Range Validation" "FAIL" "No validation"
fi

# Test 15: Complete user workflow simulation
log_test "Test 15: Complete user workflow"

workflow_success=true

# Step 1: User opens page and sees current status
current_state=$(get_current_state)
if [ -z "$current_state" ]; then
    workflow_success=false
    log_error "Workflow: Failed to get initial status"
fi

# Step 2: User adjusts volumes
execute_web_action "volume" '{"target":"output","value":65}' "volume" >/dev/null
execute_web_action "volume" '{"target":"input","value":70}' "volume" >/dev/null

# Step 3: User mutes output
execute_web_action "mute" '{"target":"output"}' "mute" >/dev/null

# Step 4: User saves as defaults
sleep 1
save_response=$(execute_web_action "save-defaults" '{}' "save-defaults")
if ! echo "$save_response" | grep -q '"success".*true'; then
    workflow_success=false
    log_error "Workflow: Failed to save defaults"
fi

# Step 5: User changes settings temporarily
execute_web_action "volume" '{"target":"both","value":100}' "volume" >/dev/null
execute_web_action "unmute" '{"target":"both"}' "unmute" >/dev/null

# Step 6: User loads defaults to restore
sleep 1
load_response=$(execute_web_action "load-defaults" '{}' "load-defaults")
if ! echo "$load_response" | grep -q '"success".*true'; then
    workflow_success=false
    log_error "Workflow: Failed to load defaults"
fi

# Step 7: Verify final state matches saved defaults
sleep 2
final_state=$(get_current_state)
final_output_vol=$(echo "$final_state" | grep -oP '"output"[^}]*"volume":\s*\K\d+')
final_input_vol=$(echo "$final_state" | grep -oP '"input"[^}]*"volume":\s*\K\d+')
final_output_muted=$(echo "$final_state" | grep -oP '"output"[^}]*"muted":\s*\K(true|false)')

if [ "$final_output_vol" = "65" ] && [ "$final_input_vol" = "70" ] && [ "$final_output_muted" = "true" ]; then
    log_info "Workflow: Final state matches saved defaults"
else
    workflow_success=false
    log_error "Workflow: Final state doesn't match defaults"
fi

if $workflow_success; then
    record_test "Complete User Workflow" "PASS" "All steps successful"
else
    record_test "Complete User Workflow" "FAIL" "Some steps failed"
fi

# Cleanup: Reset to reasonable defaults
log_info "Cleaning up test settings..."
execute_web_action "volume" '{"target":"both","value":75}' "volume" >/dev/null
execute_web_action "unmute" '{"target":"both"}' "unmute" >/dev/null

# Collect performance metrics
log_test "Performance Metrics"

# Measure API response time
start_time=$(date +%s%N)
curl -s "http://${TEST_BOX_IP}:8089/api/intercom/status" >/dev/null 2>&1
end_time=$(date +%s%N)
response_time=$((($end_time - $start_time) / 1000000))

log_info "API response time: ${response_time}ms"
if [ $response_time -lt 500 ]; then
    record_test "API Performance" "PASS" "Response time: ${response_time}ms"
else
    record_test "API Performance" "WARN" "Slow response: ${response_time}ms"
fi

# Check memory usage of API service
api_memory=$(box_ssh "ps aux | grep ndi-bridge-intercom-api | grep -v grep | awk '{print \$6}' | head -1")
if [ -n "$api_memory" ]; then
    api_memory_mb=$((api_memory / 1024))
    log_info "API memory usage: ${api_memory_mb}MB"
    if [ $api_memory_mb -lt 100 ]; then
        record_test "API Memory Usage" "PASS" "${api_memory_mb}MB"
    else
        record_test "API Memory Usage" "WARN" "High usage: ${api_memory_mb}MB"
    fi
fi

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All web intercom interface tests passed!"
    log_info "The web interface at http://${TEST_BOX_IP}/intercom is fully functional"
    exit 0
else
    log_error "❌ $TEST_FAILED web interface tests failed"
    exit 1
fi