#!/bin/bash
# Basic functionality test suite
# Tests core NDI Bridge functionality without external dependencies

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Basic Functionality Test Suite"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Test 1: Core services
log_test "Test 1: Core services"

# Check capture service
if assert_service_active "ndi-capture"; then
    record_test "NDI Capture Service" "PASS"
else
    record_test "NDI Capture Service" "FAIL" "Core service not running"
fi

# Check nginx
nginx_status=$(box_ssh "systemctl is-active nginx" | tr -d '\n')
if [ "$nginx_status" = "active" ]; then
    record_test "Web Server" "PASS"
else
    record_test "Web Server" "FAIL" "Nginx not running"
fi

# Test 2: Capture functionality
log_test "Test 2: Capture functionality"

if box_check_capture_device; then
    record_test "Capture Device" "PASS"
    
    # Check capture metrics
    sleep 3
    capture_status=$(box_get_capture_status)
    if [ -n "$capture_status" ]; then
        record_test "Capture Metrics" "PASS"
        
        fps=$(parse_status_value "$capture_status" "CURRENT_FPS")
        if assert_fps_in_range "$fps"; then
            record_test "Capture FPS" "PASS" "FPS: $fps"
        else
            record_test "Capture FPS" "WARN" "FPS: $fps (expected ~60)"
        fi
    else
        record_test "Capture Metrics" "WARN" "No metrics available"
    fi
else
    record_test "Capture Device" "FAIL" "No capture device found"
fi

# Test 3: Network configuration
log_test "Test 3: Network configuration"

if box_check_network; then
    record_test "Network IP" "PASS"
else
    record_test "Network IP" "FAIL" "No IP address"
fi

# Check bridge interface
bridge_status=$(box_ssh "ip link show br0 2>/dev/null | grep -c 'state UP'")
if [ "$bridge_status" = "1" ]; then
    record_test "Bridge Interface" "PASS"
else
    record_test "Bridge Interface" "WARN" "Bridge not UP"
fi

# Test 4: Web interface
log_test "Test 4: Web interface"

response=$(curl -s -o /dev/null -w "%{http_code}" -m 5 --user admin:newlevel "http://${TEST_BOX_IP}/" 2>/dev/null)
if [ "$response" = "200" ]; then
    record_test "Web Access" "PASS"
else
    record_test "Web Access" "FAIL" "HTTP status: $response"
fi

# Test 5: Helper scripts
log_test "Test 5: Helper scripts"

# Check if basic helper scripts exist
scripts="ndi-bridge-info ndi-bridge-logs ndi-bridge-rw ndi-bridge-ro"
missing=0
for script in $scripts; do
    if box_ssh "which /usr/local/bin/$script >/dev/null 2>&1"; then
        log_info "✓ $script exists"
    else
        log_warn "✗ $script missing"
        missing=$((missing + 1))
    fi
done

if [ $missing -eq 0 ]; then
    record_test "Helper Scripts" "PASS" "All basic scripts present"
else
    record_test "Helper Scripts" "WARN" "$missing scripts missing"
fi

# Test 6: Display capability
log_test "Test 6: Display capability"

# Just check if display binary exists
if box_ssh "test -x /opt/ndi-bridge/ndi-display"; then
    record_test "Display Binary" "PASS"
    
    # Can't assign capture stream to display (would create loop)
    # Just verify display service template exists
    display_enabled=$(box_ssh "systemctl list-unit-files | grep -c 'ndi-display@.service'")
    if [ "$display_enabled" = "1" ]; then
        record_test "Display Service Template" "PASS"
    else
        record_test "Display Service Template" "FAIL" "Display service template not found"
    fi
else
    record_test "Display Binary" "FAIL" "NDI display not installed"
fi

# Test 7: Filesystem state
log_test "Test 7: Filesystem state"

mount_state=$(box_ssh "mount | grep ' / ' | grep -o 'r[ow]' | head -1")
if [ "$mount_state" = "ro" ]; then
    record_test "Read-Only Filesystem" "PASS"
elif [ "$mount_state" = "rw" ]; then
    record_test "Read-Only Filesystem" "WARN" "Filesystem is read-write"
else
    record_test "Read-Only Filesystem" "FAIL" "Unknown mount state"
fi

# Test 8: System resources
log_test "Test 8: System resources"

# Check memory usage
mem_free=$(box_ssh "free -m | grep Mem | awk '{print \$7}'")
if [ "$mem_free" -gt 100 ]; then
    record_test "Memory Available" "PASS" "${mem_free}MB free"
else
    record_test "Memory Available" "WARN" "Low memory: ${mem_free}MB"
fi

# Check disk usage
disk_usage=$(box_ssh "df -h / | tail -1 | awk '{print \$5}' | tr -d '%'")
if [ "$disk_usage" -lt 90 ]; then
    record_test "Disk Usage" "PASS" "${disk_usage}% used"
else
    record_test "Disk Usage" "WARN" "High disk usage: ${disk_usage}%"
fi

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All basic tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED basic tests failed"
    exit 1
fi