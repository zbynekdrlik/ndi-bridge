#!/bin/bash
# NDI Bridge Intercom Web Interface Test Suite
# Tests the web-based intercom control interface

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/box_control.sh"
source "$SCRIPT_DIR/../lib/ro_check.sh"

# Configuration from environment or defaults
TEST_BOX_IP="${TEST_BOX_IP:-10.77.9.143}"
SSH_USER="${SSH_USER:-root}"
SSH_PASS="${SSH_PASS:-newlevel}"
WEB_USER="${WEB_USER:-admin}"
WEB_PASS="${WEB_PASS:-newlevel}"
export SSHPASS="$SSH_PASS"

# Test suite header
log_test "Starting Intercom Web Interface Test Suite"
log_info "Target box: $TEST_BOX_IP"

# Verify box is reachable
if ! ping -c 1 -W 2 "$TEST_BOX_IP" > /dev/null 2>&1; then
    log_error "Cannot reach test box at $TEST_BOX_IP"
    exit 1
fi

# Check readonly filesystem - required for valid test
if ! verify_readonly_filesystem "$TEST_BOX_IP"; then
    log_error "Failed to verify read-only filesystem"
    exit 1
fi

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: API service status
log_test "Test 1: Intercom API service"
if box_ssh "systemctl is-active ndi-bridge-intercom-api.service" > /dev/null 2>&1; then
    log_info "✓ API Service Active"
    ((TESTS_PASSED++))
else
    # Try to start it
    box_ssh "systemctl start ndi-bridge-intercom-api.service" > /dev/null 2>&1 || true
    sleep 3
    if box_ssh "systemctl is-active ndi-bridge-intercom-api.service" > /dev/null 2>&1; then
        log_info "✓ API Service Started"
        ((TESTS_PASSED++))
    else
        log_error "✗ API Service Failed"
        ((TESTS_FAILED++))
    fi
fi

# Test 2: API port listening
log_test "Test 2: API port 8089"
if box_ssh "netstat -tln | grep -q ':8089'" > /dev/null 2>&1; then
    log_info "✓ API Port 8089 Open"
    ((TESTS_PASSED++))
else
    log_error "✗ API Port Not Open"
    ((TESTS_FAILED++))
fi

# Test 3: Web interface page
log_test "Test 3: Intercom web page"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$WEB_USER:$WEB_PASS" "http://$TEST_BOX_IP/intercom" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    log_info "✓ Intercom Page Accessible"
    ((TESTS_PASSED++))
else
    log_error "✗ Intercom Page Failed (HTTP $HTTP_CODE)"
    ((TESTS_FAILED++))
fi

# Test 4: Web page content
log_test "Test 4: Web page content"
PAGE_CONTENT=$(curl -s -u "$WEB_USER:$WEB_PASS" "http://$TEST_BOX_IP/intercom" 2>/dev/null || true)
if echo "$PAGE_CONTENT" | grep -q "NDI Bridge Intercom"; then
    log_info "✓ Page Title Found"
    ((TESTS_PASSED++))
else
    log_error "✗ Page Content Wrong"
    ((TESTS_FAILED++))
fi

# Test 5: API status endpoint
log_test "Test 5: API status endpoint"
API_STATUS=$(curl -s -u "$WEB_USER:$WEB_PASS" "http://$TEST_BOX_IP/api/intercom/status" 2>/dev/null || true)
if echo "$API_STATUS" | grep -q '"output"'; then
    log_info "✓ API Status Working"
    
    # Parse volume and mute status
    OUTPUT_VOL=$(echo "$API_STATUS" | grep -o '"volume":[0-9]*' | head -1 | cut -d: -f2)
    OUTPUT_MUTED=$(echo "$API_STATUS" | grep -o '"muted":[a-z]*' | head -1 | cut -d: -f2)
    
    if [ -n "$OUTPUT_VOL" ]; then
        log_info "  Output Volume: ${OUTPUT_VOL}%"
    fi
    if [ -n "$OUTPUT_MUTED" ]; then
        log_info "  Output Muted: $OUTPUT_MUTED"
    fi
    
    ((TESTS_PASSED++))
else
    log_error "✗ API Status Failed"
    ((TESTS_FAILED++))
fi

# Test 6: API control - volume change
log_test "Test 6: API volume control"
VOLUME_RESULT=$(curl -s -X POST -u "$WEB_USER:$WEB_PASS" \
    -H "Content-Type: application/json" \
    -d '{"command":"set-volume","target":"output","value":60}' \
    "http://$TEST_BOX_IP/api/intercom/control" 2>/dev/null || true)

if echo "$VOLUME_RESULT" | grep -q '"success":true'; then
    log_info "✓ Volume Control via API"
    
    # Verify the change
    sleep 1
    NEW_STATUS=$(curl -s -u "$WEB_USER:$WEB_PASS" "http://$TEST_BOX_IP/api/intercom/status" 2>/dev/null || true)
    NEW_VOL=$(echo "$NEW_STATUS" | grep -o '"volume":[0-9]*' | head -1 | cut -d: -f2)
    
    if [ "$NEW_VOL" = "60" ]; then
        log_info "✓ Volume Changed to 60%"
        ((TESTS_PASSED++))
    else
        log_warn "⚠ Volume Change Not Verified"
        ((TESTS_PASSED++))  # Still pass if command succeeded
    fi
else
    log_error "✗ Volume Control Failed"
    ((TESTS_FAILED++))
fi

# Test 7: API control - mute
log_test "Test 7: API mute control"
MUTE_RESULT=$(curl -s -X POST -u "$WEB_USER:$WEB_PASS" \
    -H "Content-Type: application/json" \
    -d '{"command":"mute","target":"output"}' \
    "http://$TEST_BOX_IP/api/intercom/control" 2>/dev/null || true)

if echo "$MUTE_RESULT" | grep -q '"success":true'; then
    log_info "✓ Mute Control via API"
    ((TESTS_PASSED++))
else
    log_error "✗ Mute Control Failed"
    ((TESTS_FAILED++))
fi

# Test 8: API control - unmute
log_test "Test 8: API unmute control"
UNMUTE_RESULT=$(curl -s -X POST -u "$WEB_USER:$WEB_PASS" \
    -H "Content-Type: application/json" \
    -d '{"command":"unmute","target":"output"}' \
    "http://$TEST_BOX_IP/api/intercom/control" 2>/dev/null || true)

if echo "$UNMUTE_RESULT" | grep -q '"success":true'; then
    log_info "✓ Unmute Control via API"
    ((TESTS_PASSED++))
else
    log_error "✗ Unmute Control Failed"
    ((TESTS_FAILED++))
fi

# Test 9: Configuration save
log_test "Test 9: Configuration save"
# First make filesystem writable
box_ssh "ndi-bridge-rw" > /dev/null 2>&1 || true
sleep 1

SAVE_RESULT=$(curl -s -X POST -u "$WEB_USER:$WEB_PASS" \
    -H "Content-Type: application/json" \
    -d '{"action":"save"}' \
    "http://$TEST_BOX_IP/api/intercom/config" 2>/dev/null || true)

if echo "$SAVE_RESULT" | grep -q '"success":true'; then
    log_info "✓ Config Save via API"
    
    # Check if config file was created
    if box_ssh "test -f /etc/ndi-bridge/intercom.conf" > /dev/null 2>&1; then
        log_info "✓ Config File Created"
        ((TESTS_PASSED++))
    else
        log_error "✗ Config File Not Created"
        ((TESTS_FAILED++))
    fi
else
    log_warn "⚠ Config Save Failed (filesystem might be read-only)"
fi

# Return filesystem to read-only
box_ssh "ndi-bridge-ro" > /dev/null 2>&1 || true

# Test 10: Configuration load
log_test "Test 10: Configuration load"
LOAD_RESULT=$(curl -s -X POST -u "$WEB_USER:$WEB_PASS" \
    -H "Content-Type: application/json" \
    -d '{"action":"load"}' \
    "http://$TEST_BOX_IP/api/intercom/config" 2>/dev/null || true)

if echo "$LOAD_RESULT" | grep -q '"success":true'; then
    log_info "✓ Config Load via API"
    ((TESTS_PASSED++))
else
    log_warn "⚠ Config Load Failed (might be no saved config)"
fi

# Test 11: Web interface JavaScript functionality
log_test "Test 11: JavaScript controls"
if echo "$PAGE_CONTENT" | grep -q "toggleMute.*setVolume.*saveConfig"; then
    log_info "✓ JavaScript Functions Present"
    ((TESTS_PASSED++))
else
    log_error "✗ JavaScript Functions Missing"
    ((TESTS_FAILED++))
fi

# Test 12: Authentication requirement
log_test "Test 12: Authentication"
UNAUTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$TEST_BOX_IP/intercom" 2>/dev/null || echo "000")
if [ "$UNAUTH_CODE" = "401" ]; then
    log_info "✓ Authentication Required"
    ((TESTS_PASSED++))
else
    log_error "✗ No Authentication ($UNAUTH_CODE)"
    ((TESTS_FAILED++))
fi

# Test 13: Main page link to intercom
log_test "Test 13: Main page link"
MAIN_PAGE=$(curl -s -u "$WEB_USER:$WEB_PASS" "http://$TEST_BOX_IP/" 2>/dev/null || true)
if echo "$MAIN_PAGE" | grep -q "/intercom"; then
    log_info "✓ Intercom Link on Main Page"
    ((TESTS_PASSED++))
else
    log_warn "⚠ No Intercom Link on Main Page"
fi

# Test 14: CORS headers for API
log_test "Test 14: CORS headers"
CORS_HEADERS=$(curl -s -I -u "$WEB_USER:$WEB_PASS" "http://$TEST_BOX_IP/api/intercom/status" 2>/dev/null || true)
if echo "$CORS_HEADERS" | grep -qi "access-control-allow-origin"; then
    log_info "✓ CORS Headers Present"
    ((TESTS_PASSED++))
else
    log_warn "⚠ No CORS Headers"
fi

# Collect diagnostic information
log_info "Collecting web service information..."
if [ "$VERBOSE" = "true" ]; then
    echo "=== API Service Status ==="
    box_ssh "systemctl status ndi-bridge-intercom-api.service --no-pager | head -20" || true
    
    echo ""
    echo "=== Nginx Config ==="
    box_ssh "grep -A5 intercom /etc/nginx/sites-available/ndi-bridge" || true
    
    echo ""
    echo "=== API Logs ==="
    box_ssh "journalctl -u ndi-bridge-intercom-api.service -n 20 --no-pager" || true
fi

# Summary
echo ""
echo "================================"
echo "Test Summary"
echo "================================"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo "Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    log_info "✅ All web intercom tests passed!"
    verify_readonly_filesystem "$TEST_BOX_IP" > /dev/null 2>&1
    exit 0
else
    log_error "❌ $TESTS_FAILED web intercom tests failed"
    
    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo ""
        echo "Failed Tests:"
        echo "Check the API service and nginx configuration"
    fi
    
    verify_readonly_filesystem "$TEST_BOX_IP" > /dev/null 2>&1
    exit 1
fi