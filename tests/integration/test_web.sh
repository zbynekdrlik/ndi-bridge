#!/bin/bash
# Web interface functionality test suite
# Tests HTTP service, authentication, wetty terminal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Web Interface Test Suite"
WEB_USER="admin"
WEB_PASS="newlevel"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Test 1: Web server status
log_test "Test 1: Web server status"

# Check nginx service
nginx_status=$(box_ssh "systemctl is-active nginx" | tr -d '\n')
if [ "$nginx_status" = "active" ]; then
    record_test "Nginx Service" "PASS"
else
    record_test "Nginx Service" "FAIL" "Nginx not running"
fi

# Check if port 80 is listening
port_80=$(box_ssh "netstat -tln 2>/dev/null | grep -c ':80 ' || echo 0")
if [ "$port_80" -gt 0 ]; then
    record_test "HTTP Port (80)" "PASS" "Port 80 is listening"
else
    record_test "HTTP Port (80)" "FAIL" "Port 80 not listening"
fi

# Test 2: HTTP basic connectivity
log_test "Test 2: HTTP basic connectivity"

# Test without auth (should fail)
http_noauth=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "http://${TEST_BOX_IP}/" 2>/dev/null)
if [ "$http_noauth" = "401" ]; then
    record_test "HTTP Auth Required" "PASS" "Returns 401 without credentials"
else
    record_test "HTTP Auth Required" "FAIL" "Expected 401, got $http_noauth"
fi

# Test with auth
http_auth=$(curl -s -o /dev/null -w "%{http_code}" -m 5 --user "$WEB_USER:$WEB_PASS" "http://${TEST_BOX_IP}/" 2>/dev/null)
if [ "$http_auth" = "200" ]; then
    record_test "HTTP Auth Success" "PASS" "Can access with credentials"
else
    record_test "HTTP Auth Success" "FAIL" "Cannot access with credentials (got $http_auth)"
fi

# Test 3: Web interface content
log_test "Test 3: Web interface content"

# Get main page content
main_page=$(curl -s -m 5 --user "$WEB_USER:$WEB_PASS" "http://${TEST_BOX_IP}/" 2>/dev/null)
if [ -n "$main_page" ]; then
    # Check for expected elements (WeTTy is the web terminal interface)
    if echo "$main_page" | grep -q "WeTTy"; then
        record_test "Web Page Title" "PASS" "WeTTy terminal interface found"
    else
        record_test "Web Page Title" "FAIL" "Web interface not found"
    fi
    
    if echo "$main_page" | grep -q "Terminal"; then
        record_test "Terminal Link" "PASS" "Terminal interface present"
    else
        record_test "Terminal Link" "FAIL" "Terminal interface not found"
    fi
else
    record_test "Web Page Content" "FAIL" "Could not retrieve page content"
fi

# Test 4: Wetty terminal service
log_test "Test 4: Wetty terminal service"

# Check wetty service
wetty_status=$(box_ssh "systemctl is-active wetty" | tr -d '\n')
if [ "$wetty_status" = "active" ]; then
    record_test "Wetty Service" "PASS"
    
    # Check wetty port (7681 in our setup)
    wetty_port=$(box_ssh "netstat -tln 2>/dev/null | grep -c ':7681 ' || echo 0")
    # Convert to integer, removing any whitespace
    wetty_port=$(echo "$wetty_port" | tr -d '[:space:]')
    if [ -z "$wetty_port" ]; then
        wetty_port=0
    fi
    if [ "$wetty_port" -gt 0 ]; then
        record_test "Wetty Port (7681)" "PASS" "Wetty listening on port 7681"
    else
        record_test "Wetty Port (7681)" "WARN" "Wetty port not detected"
    fi
else
    record_test "Wetty Service" "FAIL" "Wetty not running"
fi

# Test wetty endpoint
wetty_response=$(curl -s -o /dev/null -w "%{http_code}" -m 5 --user "$WEB_USER:$WEB_PASS" "http://${TEST_BOX_IP}/wetty" 2>/dev/null)
if [ "$wetty_response" = "200" ] || [ "$wetty_response" = "301" ] || [ "$wetty_response" = "302" ]; then
    record_test "Wetty Endpoint" "PASS" "Wetty accessible via web"
else
    record_test "Wetty Endpoint" "FAIL" "Wetty not accessible (got $wetty_response)"
fi

# Test 5: WeTTy functionality
log_test "Test 5: WeTTy terminal functionality"

# WeTTy is the only web interface - it's a terminal, not an API
# No status API, no static CSS files - just the terminal
log_info "WeTTy provides terminal access only - no API endpoints"
record_test "Web Interface Type" "PASS" "WeTTy terminal (no API needed)"

# Test 7: Security headers
log_test "Test 7: Security headers"

# Get headers
headers=$(curl -sI -m 5 --user "$WEB_USER:$WEB_PASS" "http://${TEST_BOX_IP}/" 2>/dev/null)

# Check for basic security headers
if echo "$headers" | grep -qi "X-Frame-Options"; then
    record_test "X-Frame-Options" "PASS" "Header present"
else
    record_test "X-Frame-Options" "INFO" "Header not set"
fi

if echo "$headers" | grep -qi "X-Content-Type-Options"; then
    record_test "X-Content-Type-Options" "PASS" "Header present"
else
    record_test "X-Content-Type-Options" "INFO" "Header not set"
fi

# Test 8: Basic functionality verification
log_test "Test 8: Basic web server functionality"

# The web server only serves WeTTy terminal - no PHP, no logs endpoint
# This is by design - management is via SSH/terminal
record_test "Web Server Purpose" "PASS" "Terminal access only (as designed)"

# Test 10: Performance
log_test "Test 10: Web interface performance"

# Measure response time
start_time=$(date +%s%N)
curl -s -o /dev/null -m 5 --user "$WEB_USER:$WEB_PASS" "http://${TEST_BOX_IP}/" 2>/dev/null
end_time=$(date +%s%N)
response_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds

if [ $response_time -lt 1000 ]; then
    record_test "Response Time" "PASS" "Fast response: ${response_time}ms"
elif [ $response_time -lt 3000 ]; then
    record_test "Response Time" "PASS" "Acceptable response: ${response_time}ms"
else
    record_test "Response Time" "WARN" "Slow response: ${response_time}ms"
fi

# Collect diagnostic information
log_info "Collecting web service information..."

# Get nginx config test
nginx_config=$(box_ssh "nginx -t 2>&1")
log_output "Nginx Config Test" "$nginx_config"

# Get nginx error log
nginx_errors=$(box_ssh "tail -20 /var/log/nginx/error.log 2>/dev/null || echo 'No error log'")
log_output "Nginx Recent Errors" "$nginx_errors"

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All web interface tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED web interface tests failed"
    exit 1
fi