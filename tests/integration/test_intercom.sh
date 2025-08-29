#!/bin/bash
# Intercom functionality test suite
# Tests web interface, audio control, and configuration persistence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"
source "${SCRIPT_DIR}/../lib/ro_check.sh"

# Test configuration
TEST_NAME="Intercom Control Test Suite"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Verify filesystem is read-only before testing
if ! verify_readonly_filesystem; then
    exit 1
fi

# Test 1: Check intercom service renaming
log_test "Test 1: Service renaming verification"

# Check if old vdo-ninja service exists
old_service_exists=$(box_ssh "systemctl list-unit-files | grep -c vdo-ninja-intercom.service || echo 0")
new_service_exists=$(box_ssh "systemctl list-unit-files | grep -c ndi-bridge-intercom.service || echo 0")

if [ "$new_service_exists" -gt 0 ]; then
    record_test "Service Renamed" "PASS" "ndi-bridge-intercom.service found"
else
    # Check if we can find the old service (for backward compat)
    if [ "$old_service_exists" -gt 0 ]; then
        record_test "Service Renamed" "WARN" "Still using old vdo-ninja-intercom.service"
        # Use old service name for remaining tests
        INTERCOM_SERVICE="vdo-ninja-intercom.service"
    else
        record_test "Service Renamed" "FAIL" "No intercom service found"
        INTERCOM_SERVICE="ndi-bridge-intercom.service"
    fi
fi

# Test 2: Check control script availability
log_test "Test 2: Control script availability"

control_scripts=(
    "ndi-bridge-intercom-control"
    "ndi-bridge-intercom-config"
    "ndi-bridge-intercom-status"
    "ndi-bridge-intercom-logs"
    "ndi-bridge-intercom-restart"
)

all_scripts_present=true
for script in "${control_scripts[@]}"; do
    if box_ssh "[ -x /usr/local/bin/$script ]"; then
        log_info "  ✓ $script present and executable"
    else
        log_error "  ✗ $script missing or not executable"
        all_scripts_present=false
    fi
done

if $all_scripts_present; then
    record_test "Control Scripts" "PASS" "All scripts present"
else
    record_test "Control Scripts" "FAIL" "Some scripts missing"
fi

# Test 3: Intercom API service
log_test "Test 3: Intercom API service"

api_status=$(box_ssh "systemctl is-active ndi-bridge-intercom-api.service" | tr -d '\n')
if [ "$api_status" = "active" ]; then
    record_test "API Service" "PASS" "Service active"
    
    # Check if API responds
    api_response=$(curl -s -o /dev/null -w "%{http_code}" "http://${TEST_BOX_IP}:8089/api/intercom/health" 2>/dev/null)
    if [ "$api_response" = "200" ]; then
        record_test "API Health Check" "PASS" "API responding"
    else
        record_test "API Health Check" "FAIL" "API not responding (HTTP $api_response)"
    fi
else
    record_test "API Service" "FAIL" "Service not active: $api_status"
    
    # Try to start it
    log_info "Attempting to start API service..."
    box_ssh "systemctl start ndi-bridge-intercom-api.service"
    sleep 2
    
    api_status=$(box_ssh "systemctl is-active ndi-bridge-intercom-api.service" | tr -d '\n')
    if [ "$api_status" = "active" ]; then
        record_test "API Service Recovery" "PASS" "Service started"
    else
        record_test "API Service Recovery" "FAIL" "Could not start service"
    fi
fi

# Test 4: Web interface accessibility
log_test "Test 4: Web interface accessibility"

# Check main page
main_page=$(curl -s -o /dev/null -w "%{http_code}" --user admin:newlevel "http://${TEST_BOX_IP}/" 2>/dev/null)
if [ "$main_page" = "200" ]; then
    record_test "Main Web Page" "PASS" "Accessible"
else
    record_test "Main Web Page" "FAIL" "HTTP $main_page"
fi

# Check intercom page
intercom_page=$(curl -s -o /dev/null -w "%{http_code}" --user admin:newlevel "http://${TEST_BOX_IP}/intercom" 2>/dev/null)
if [ "$intercom_page" = "200" ]; then
    record_test "Intercom Web Page" "PASS" "Accessible"
else
    record_test "Intercom Web Page" "FAIL" "HTTP $intercom_page"
fi

# Test 5: Audio control functionality
log_test "Test 5: Audio control functionality"

# Start intercom service if not running
intercom_active=$(box_ssh "systemctl is-active ndi-bridge-intercom.service" | tr -d '\n')
if [ "$intercom_active" != "active" ]; then
    log_info "Starting intercom service..."
    box_ssh "systemctl start ndi-bridge-intercom.service"
    sleep 5
fi

# Get initial status
status_output=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control status 2>/dev/null")
if [ -n "$status_output" ]; then
    record_test "Control Status Command" "PASS" "Status retrieved"
    log_output "Initial Status" "$status_output"
    
    # Parse initial volumes
    initial_output_vol=$(echo "$status_output" | grep -A2 '"output"' | grep '"volume"' | grep -oP '\d+' || echo "75")
    initial_input_vol=$(echo "$status_output" | grep -A2 '"input"' | grep '"volume"' | grep -oP '\d+' || echo "75")
    
    log_info "Initial volumes - Output: ${initial_output_vol}%, Input: ${initial_input_vol}%"
else
    record_test "Control Status Command" "FAIL" "Could not get status"
    initial_output_vol=75
    initial_input_vol=75
fi

# Test 6: Volume control
log_test "Test 6: Volume control"

# Set output volume to 50%
vol_result=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control volume output 50 2>&1")
if echo "$vol_result" | grep -q "Output volume set to 50%"; then
    record_test "Set Output Volume" "PASS" "Volume set to 50%"
else
    record_test "Set Output Volume" "FAIL" "$vol_result"
fi

# Set input volume to 60%
vol_result=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control volume input 60 2>&1")
if echo "$vol_result" | grep -q "Input volume set to 60%"; then
    record_test "Set Input Volume" "PASS" "Volume set to 60%"
else
    record_test "Set Input Volume" "FAIL" "$vol_result"
fi

# Verify volumes changed
sleep 1
status_output=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control status 2>/dev/null")
new_output_vol=$(echo "$status_output" | grep -A2 '"output"' | grep '"volume"' | grep -oP '\d+' || echo "0")
new_input_vol=$(echo "$status_output" | grep -A2 '"input"' | grep '"volume"' | grep -oP '\d+' || echo "0")

if [ "$new_output_vol" = "50" ]; then
    record_test "Output Volume Verification" "PASS" "Volume is 50%"
else
    record_test "Output Volume Verification" "FAIL" "Expected 50%, got $new_output_vol%"
fi

if [ "$new_input_vol" = "60" ]; then
    record_test "Input Volume Verification" "PASS" "Volume is 60%"
else
    record_test "Input Volume Verification" "FAIL" "Expected 60%, got $new_input_vol%"
fi

# Test 7: Mute functionality
log_test "Test 7: Mute functionality"

# Mute output
mute_result=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control mute output 2>&1")
if echo "$mute_result" | grep -q "Output muted"; then
    record_test "Mute Output" "PASS" "Output muted"
else
    record_test "Mute Output" "FAIL" "$mute_result"
fi

# Check mute status
status_output=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control status 2>/dev/null")
output_muted=$(echo "$status_output" | grep -A2 '"output"' | grep '"muted"' | grep -o 'true\|false')

if [ "$output_muted" = "true" ]; then
    record_test "Mute Status" "PASS" "Output is muted"
else
    record_test "Mute Status" "FAIL" "Output not muted"
fi

# Unmute output
unmute_result=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control unmute output 2>&1")
if echo "$unmute_result" | grep -q "Output unmuted"; then
    record_test "Unmute Output" "PASS" "Output unmuted"
else
    record_test "Unmute Output" "FAIL" "$unmute_result"
fi

# Test 8: Toggle functionality
log_test "Test 8: Toggle mute functionality"

# Get initial mute state
status_output=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control status 2>/dev/null")
initial_muted=$(echo "$status_output" | grep -A2 '"input"' | grep '"muted"' | grep -o 'true\|false')

# Toggle input mute
toggle_result=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control toggle input 2>&1")
if echo "$toggle_result" | grep -q "Input"; then
    record_test "Toggle Mute" "PASS" "Toggle executed"
else
    record_test "Toggle Mute" "FAIL" "$toggle_result"
fi

# Verify state changed
status_output=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control status 2>/dev/null")
new_muted=$(echo "$status_output" | grep -A2 '"input"' | grep '"muted"' | grep -o 'true\|false')

if [ "$initial_muted" != "$new_muted" ]; then
    record_test "Toggle Verification" "PASS" "State toggled from $initial_muted to $new_muted"
else
    record_test "Toggle Verification" "FAIL" "State unchanged: $new_muted"
fi

# Toggle back
box_ssh "/usr/local/bin/ndi-bridge-intercom-control toggle input" >/dev/null 2>&1

# Test 9: Configuration save/load
log_test "Test 9: Configuration persistence"

# Set specific values
box_ssh "/usr/local/bin/ndi-bridge-intercom-control volume output 85" >/dev/null 2>&1
box_ssh "/usr/local/bin/ndi-bridge-intercom-control volume input 90" >/dev/null 2>&1
box_ssh "/usr/local/bin/ndi-bridge-intercom-control mute output" >/dev/null 2>&1

# Save configuration (need to simulate 'y' response)
save_result=$(box_ssh "echo 'y' | /usr/local/bin/ndi-bridge-intercom-config save 2>&1")
if echo "$save_result" | grep -q "Default settings saved successfully"; then
    record_test "Save Configuration" "PASS" "Settings saved"
else
    record_test "Save Configuration" "FAIL" "Could not save settings"
fi

# Check if config file was created
config_exists=$(box_ssh "[ -f /etc/ndi-bridge/intercom.conf ] && echo 'yes' || echo 'no'")
if [ "$config_exists" = "yes" ]; then
    record_test "Config File Created" "PASS" "File exists"
    
    # Display config
    config_content=$(box_ssh "cat /etc/ndi-bridge/intercom.conf 2>/dev/null")
    log_output "Saved Configuration" "$config_content"
else
    record_test "Config File Created" "FAIL" "File not created"
fi

# Change values
box_ssh "/usr/local/bin/ndi-bridge-intercom-control volume output 30" >/dev/null 2>&1
box_ssh "/usr/local/bin/ndi-bridge-intercom-control unmute output" >/dev/null 2>&1

# Load saved configuration
load_result=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-config apply 2>&1")
if echo "$load_result" | grep -q "Default settings applied"; then
    record_test "Load Configuration" "PASS" "Settings loaded"
else
    record_test "Load Configuration" "FAIL" "Could not load settings"
fi

# Verify loaded values
status_output=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-control status 2>/dev/null")
loaded_output_vol=$(echo "$status_output" | grep -A2 '"output"' | grep '"volume"' | grep -oP '\d+')
loaded_output_muted=$(echo "$status_output" | grep -A2 '"output"' | grep '"muted"' | grep -o 'true\|false')

if [ "$loaded_output_vol" = "85" ] && [ "$loaded_output_muted" = "true" ]; then
    record_test "Configuration Restore" "PASS" "Values restored correctly"
else
    record_test "Configuration Restore" "FAIL" "Got vol=$loaded_output_vol muted=$loaded_output_muted"
fi

# Test 10: Status command output
log_test "Test 10: Status command comprehensive output"

status_cmd_output=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-status 2>/dev/null")
if [ -n "$status_cmd_output" ]; then
    record_test "Status Command" "PASS" "Command executed"
    
    # Check for expected sections
    if echo "$status_cmd_output" | grep -q "Service Status:"; then
        record_test "Status - Service Info" "PASS" "Service section present"
    else
        record_test "Status - Service Info" "FAIL" "Service section missing"
    fi
    
    if echo "$status_cmd_output" | grep -q "Audio Configuration:"; then
        record_test "Status - Audio Info" "PASS" "Audio section present"
    else
        record_test "Status - Audio Info" "FAIL" "Audio section missing"
    fi
    
    if echo "$status_cmd_output" | grep -q "VDO.Ninja Connection:"; then
        record_test "Status - VDO Info" "PASS" "VDO.Ninja section present"
    else
        record_test "Status - VDO Info" "FAIL" "VDO.Ninja section missing"
    fi
    
    log_output "Status Command Output (first 50 lines)" "$(echo "$status_cmd_output" | head -50)"
else
    record_test "Status Command" "FAIL" "No output from command"
fi

# Test 11: API endpoint testing
log_test "Test 11: API endpoint functionality"

# Test status endpoint
api_status=$(curl -s "http://${TEST_BOX_IP}:8089/api/intercom/status" 2>/dev/null)
if [ -n "$api_status" ] && echo "$api_status" | grep -q '"service"'; then
    record_test "API Status Endpoint" "PASS" "Returns JSON status"
    log_output "API Status Response" "$api_status"
else
    record_test "API Status Endpoint" "FAIL" "Invalid response"
fi

# Test mute via API
api_mute=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"target":"output"}' \
    "http://${TEST_BOX_IP}:8089/api/intercom/mute" 2>/dev/null)
if echo "$api_mute" | grep -q '"success".*true'; then
    record_test "API Mute Endpoint" "PASS" "Mute command accepted"
else
    record_test "API Mute Endpoint" "FAIL" "Mute command failed"
fi

# Test volume via API
api_volume=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"target":"output","value":70}' \
    "http://${TEST_BOX_IP}:8089/api/intercom/volume" 2>/dev/null)
if echo "$api_volume" | grep -q '"success".*true'; then
    record_test "API Volume Endpoint" "PASS" "Volume command accepted"
else
    record_test "API Volume Endpoint" "FAIL" "Volume command failed"
fi

# Test 12: Web interface interaction
log_test "Test 12: Web interface content verification"

# Get intercom page content
intercom_html=$(curl -s --user admin:newlevel "http://${TEST_BOX_IP}/intercom" 2>/dev/null)

if echo "$intercom_html" | grep -q "NDI Bridge Intercom Control"; then
    record_test "Web Interface Title" "PASS" "Page loaded correctly"
else
    record_test "Web Interface Title" "FAIL" "Page content incorrect"
fi

# Check for key elements
if echo "$intercom_html" | grep -q "mute-button"; then
    record_test "Web Interface - Mute Button" "PASS" "Mute button present"
else
    record_test "Web Interface - Mute Button" "FAIL" "Mute button missing"
fi

if echo "$intercom_html" | grep -q "volume-slider"; then
    record_test "Web Interface - Volume Controls" "PASS" "Volume sliders present"
else
    record_test "Web Interface - Volume Controls" "FAIL" "Volume sliders missing"
fi

if echo "$intercom_html" | grep -q "saveDefaults"; then
    record_test "Web Interface - Save Defaults" "PASS" "Save defaults button present"
else
    record_test "Web Interface - Save Defaults" "FAIL" "Save defaults button missing"
fi

# Test 13: Service restart functionality
log_test "Test 13: Service restart"

restart_result=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-restart 2>&1")
if echo "$restart_result" | grep -q "restarted"; then
    record_test "Service Restart Command" "PASS" "Service restarted"
else
    record_test "Service Restart Command" "FAIL" "Restart failed"
fi

# Wait for service to stabilize
sleep 3

# Verify service is running
service_status=$(box_ssh "systemctl is-active ndi-bridge-intercom.service" | tr -d '\n')
if [ "$service_status" = "active" ]; then
    record_test "Service After Restart" "PASS" "Service active"
else
    record_test "Service After Restart" "FAIL" "Service not active: $service_status"
fi

# Test 14: Logs command
log_test "Test 14: Logs command"

logs_output=$(box_ssh "/usr/local/bin/ndi-bridge-intercom-logs 2>&1 | head -5")
if [ -n "$logs_output" ]; then
    record_test "Logs Command" "PASS" "Logs retrieved"
    log_output "Recent Logs (5 lines)" "$logs_output"
else
    record_test "Logs Command" "FAIL" "No logs retrieved"
fi

# Test 15: Filesystem remains read-only
log_test "Test 15: Filesystem protection verification"

# Verify filesystem is still read-only after all operations
if verify_readonly_filesystem; then
    record_test "Filesystem Protection" "PASS" "Still read-only after tests"
else
    record_test "Filesystem Protection" "FAIL" "Filesystem not read-only!"
fi

# Collect diagnostic information
log_info "Collecting diagnostic information..."

# Get service status
intercom_service_log=$(box_ssh "systemctl status ndi-bridge-intercom --no-pager 2>/dev/null | head -20")
log_output "Intercom Service Status" "$intercom_service_log"

api_service_log=$(box_ssh "systemctl status ndi-bridge-intercom-api --no-pager 2>/dev/null | head -20")
log_output "API Service Status" "$api_service_log"

# Check for any errors in nginx
nginx_errors=$(box_ssh "journalctl -u nginx -p err -n 10 --no-pager 2>/dev/null")
if [ -n "$nginx_errors" ]; then
    log_output "Nginx Errors" "$nginx_errors"
fi

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All intercom control tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED intercom control tests failed"
    exit 1
fi