#!/bin/bash
# Helper scripts test suite
# Tests all ndi-bridge-* helper commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Helper Scripts Test Suite"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Test 1: ndi-bridge-info command
log_test "Test 1: ndi-bridge-info"

info_output=$(box_ssh "ndi-bridge-info 2>&1")
if [ $? -eq 0 ] && [ -n "$info_output" ]; then
    record_test "ndi-bridge-info" "PASS" "Command executed successfully"
    
    # Check for expected sections
    if echo "$info_output" | grep -q "System Information"; then
        record_test "Info - System Section" "PASS"
    else
        record_test "Info - System Section" "FAIL" "Missing system information"
    fi
    
    if echo "$info_output" | grep -q "Service Status"; then
        record_test "Info - Service Status" "PASS"
    else
        record_test "Info - Service Status" "FAIL" "Missing service status"
    fi
else
    record_test "ndi-bridge-info" "FAIL" "Command failed or no output"
fi

# Test 2: ndi-bridge-logs command
log_test "Test 2: ndi-bridge-logs"

logs_output=$(box_ssh "ndi-bridge-logs 2>&1 | head -20")
if [ $? -eq 0 ] && [ -n "$logs_output" ]; then
    record_test "ndi-bridge-logs" "PASS" "Command executed successfully"
else
    record_test "ndi-bridge-logs" "FAIL" "Command failed or no output"
fi

# Test 3: ndi-bridge-rw and ndi-bridge-ro commands
log_test "Test 3: Read-write/Read-only switching"

# Get initial mount state
initial_mount=$(box_ssh "mount | grep ' / ' | grep -o 'r[wo]'")
log_info "Initial mount state: $initial_mount"

# Test switch to read-write
rw_result=$(box_ssh "ndi-bridge-rw 2>&1")
if [ $? -eq 0 ]; then
    # Verify it's actually read-write
    rw_check=$(box_ssh "mount | grep ' / ' | grep -o 'rw'")
    if [ "$rw_check" = "rw" ]; then
        record_test "ndi-bridge-rw" "PASS" "Filesystem is read-write"
    else
        record_test "ndi-bridge-rw" "FAIL" "Filesystem not read-write after command"
    fi
else
    record_test "ndi-bridge-rw" "FAIL" "Command failed"
fi

# Test switch back to read-only
ro_result=$(box_ssh "ndi-bridge-ro 2>&1")
if [ $? -eq 0 ]; then
    # Verify it's actually read-only
    ro_check=$(box_ssh "mount | grep ' / ' | grep -o 'ro' | head -1")
    if [ "$ro_check" = "ro" ]; then
        record_test "ndi-bridge-ro" "PASS" "Filesystem is read-only"
    else
        record_test "ndi-bridge-ro" "WARN" "Filesystem may not be read-only"
    fi
else
    record_test "ndi-bridge-ro" "FAIL" "Command failed"
fi

# Test 4: ndi-bridge-set-name command
log_test "Test 4: ndi-bridge-set-name"

# Save original NDI name from config
original_ndi_name=$(box_ssh "grep NDI_NAME /etc/ndi-bridge/config | cut -d'=' -f2 | tr -d '\"'")
log_info "Original NDI name: $original_ndi_name"

# The set-name command requires a parameter, not stdin
# Test with a parameter
test_name="test$(date +%s | tail -c 5)"
set_name_result=$(box_ssh "ndi-bridge-set-name $test_name 2>&1")

if echo "$set_name_result" | grep -q "successfully changed"; then
    record_test "ndi-bridge-set-name" "PASS" "Command works with parameter"
    
    # Check if hostname was actually changed
    new_hostname=$(box_ssh "hostname")
    if echo "$new_hostname" | grep -q "$test_name"; then
        record_test "Hostname Change" "PASS" "Hostname updated to include $test_name"
    else
        record_test "Hostname Change" "WARN" "Hostname not immediately updated"
    fi
    
    # IMPORTANT: Restore original name
    log_info "Restoring original NDI name: $original_ndi_name"
    if [ "$original_ndi_name" = "USB Capture" ]; then
        # USB Capture has spaces, need a different approach
        box_ssh "ndi-bridge-rw && sed -i 's/NDI_NAME=.*/NDI_NAME=\"USB Capture\"/' /etc/ndi-bridge/config && systemctl restart ndi-capture && ndi-bridge-ro" 2>/dev/null
    else
        # For simple names without spaces
        box_ssh "ndi-bridge-set-name ${original_ndi_name:-ndi-bridge} 2>/dev/null || true"
    fi
elif echo "$set_name_result" | grep -q "Usage:"; then
    record_test "ndi-bridge-set-name" "FAIL" "Command returned usage - parameter not accepted"
else
    record_test "ndi-bridge-set-name" "FAIL" "Unexpected output from set-name command"
fi

# Test 5: ndi-bridge-welcome command
log_test "Test 5: ndi-bridge-welcome"

welcome_output=$(box_ssh "ndi-bridge-welcome 2>&1")
if [ $? -eq 0 ] && [ -n "$welcome_output" ]; then
    record_test "ndi-bridge-welcome" "PASS" "Command executed successfully"
    
    # Check for expected content
    if echo "$welcome_output" | grep -q "NDI Bridge"; then
        record_test "Welcome - Header" "PASS" "Welcome screen shows header"
    else
        record_test "Welcome - Header" "FAIL" "Missing header in welcome"
    fi
else
    record_test "ndi-bridge-welcome" "FAIL" "Command failed or no output"
fi

# Test 6: ndi-bridge-help command
log_test "Test 6: ndi-bridge-help"

help_output=$(box_ssh "ndi-bridge-help 2>&1")
if [ $? -eq 0 ] && [ -n "$help_output" ]; then
    record_test "ndi-bridge-help" "PASS" "Command executed successfully"
    
    # Check for command list
    if echo "$help_output" | grep -q "Available commands"; then
        record_test "Help - Command List" "PASS" "Shows available commands"
    else
        record_test "Help - Command List" "FAIL" "Missing command list"
    fi
else
    record_test "ndi-bridge-help" "FAIL" "Command failed or no output"
fi

# Test 7: ndi-bridge-update command
log_test "Test 7: ndi-bridge-update"

# Just check if command exists and shows usage (don't actually update)
update_check=$(box_ssh "ndi-bridge-update --help 2>&1 || ndi-bridge-update 2>&1 | head -5")
if echo "$update_check" | grep -qE "update|Update|UPDATE"; then
    record_test "ndi-bridge-update" "PASS" "Update command exists"
else
    record_test "ndi-bridge-update" "INFO" "Update command may not be implemented"
fi

# Test 8: ndi-bridge-netstat command
log_test "Test 8: ndi-bridge-netstat"

netstat_output=$(box_ssh "ndi-bridge-netstat 2>&1 | head -20")
if [ $? -eq 0 ] && [ -n "$netstat_output" ]; then
    record_test "ndi-bridge-netstat" "PASS" "Command executed successfully"
    
    # Check for NDI-related ports
    if echo "$netstat_output" | grep -qE "5353|5960|5961"; then
        record_test "Netstat - NDI Ports" "PASS" "Shows NDI-related ports"
    else
        record_test "Netstat - NDI Ports" "INFO" "No NDI ports shown"
    fi
else
    record_test "ndi-bridge-netstat" "FAIL" "Command failed or no output"
fi

# Test 9: ndi-bridge-collector service/command
log_test "Test 9: ndi-bridge-collector"

collector_status=$(box_ssh "systemctl is-active ndi-bridge-collector" | tr -d '\n')
if [ "$collector_status" = "active" ]; then
    record_test "Collector Service" "PASS" "Metrics collector active"
    
    # Check if metrics files are being updated
    metrics_age=$(box_ssh "find /var/run/ndi-bridge -name '*.status' -o -name 'fps*' -mmin -1 2>/dev/null | wc -l")
    if [ "$metrics_age" -gt 0 ]; then
        record_test "Metrics Collection" "PASS" "Metrics being updated"
    else
        record_test "Metrics Collection" "WARN" "Metrics may be stale"
    fi
else
    record_test "Collector Service" "FAIL" "Collector not running"
fi

# Test 10: ndi-bridge-timesync command
log_test "Test 10: ndi-bridge-timesync"

timesync_output=$(box_ssh "ndi-bridge-timesync 2>&1 || echo 'not found'")
if [ "$timesync_output" != "not found" ]; then
    record_test "ndi-bridge-timesync" "PASS" "Command exists"
    
    # Check output
    if echo "$timesync_output" | grep -qE "PTP|NTP|sync"; then
        record_test "Timesync Output" "PASS" "Shows time sync status"
    else
        record_test "Timesync Output" "INFO" "Output format unknown"
    fi
else
    record_test "ndi-bridge-timesync" "INFO" "Command not found"
fi

# Test 11: ndi-display-config command
log_test "Test 11: ndi-display-config"

# Check if command exists
display_config=$(box_ssh "which ndi-display-config 2>/dev/null")
if [ -n "$display_config" ]; then
    record_test "ndi-display-config" "PASS" "Command exists at $display_config"
    
    # Test help/usage
    config_help=$(box_ssh "ndi-display-config --help 2>&1 || echo 'Shows menu'")
    if echo "$config_help" | grep -qE "menu|Menu|display|Display"; then
        record_test "Display Config Help" "PASS" "Command is functional"
    else
        record_test "Display Config Help" "INFO" "Interactive command"
    fi
else
    record_test "ndi-display-config" "FAIL" "Command not found"
fi

# Test 12: Check all helper scripts are executable
log_test "Test 12: Helper scripts permissions"

helper_scripts=$(box_ssh "ls -la /usr/local/bin/ndi-bridge-* 2>/dev/null | wc -l")
if [ "$helper_scripts" -gt 0 ]; then
    record_test "Helper Scripts Present" "PASS" "$helper_scripts scripts found"
    
    # Check if all are executable
    non_exec=$(box_ssh "find /usr/local/bin -name 'ndi-bridge-*' ! -perm -111 2>/dev/null | wc -l")
    if [ "$non_exec" -eq 0 ]; then
        record_test "Scripts Executable" "PASS" "All scripts are executable"
    else
        record_test "Scripts Executable" "FAIL" "$non_exec scripts not executable"
    fi
else
    record_test "Helper Scripts Present" "FAIL" "No helper scripts found"
fi

# Collect diagnostic information
log_info "Collecting helper scripts information..."

# List all ndi-bridge commands
all_commands=$(box_ssh "ls -1 /usr/local/bin/ndi-* 2>/dev/null | xargs -n1 basename")
log_output "Available NDI Commands" "$all_commands"

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All helper script tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED helper script tests failed"
    exit 1
fi