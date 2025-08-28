#!/bin/bash
# Comprehensive VDO.Ninja Intercom Test
# This test verifies not just that components are running, but that they're configured correctly

set -e

# Test configuration
SSH_HOST="${1:-}"
SERVICE="vdo-ninja-intercom"
EXPECTED_ROOM="nl_interkom"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Stats
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# SSH execution wrapper
run_command() {
    local cmd="$1"
    if [ -n "$SSH_HOST" ]; then
        sshpass -p newlevel ssh -o LogLevel=ERROR root@$SSH_HOST "$cmd"
    else
        eval "$cmd"
    fi
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Testing: $test_name... "
    
    result=$(run_command "$test_command" 2>/dev/null || echo "FAILED")
    
    if [ -n "$expected_result" ]; then
        if [ "$result" = "$expected_result" ]; then
            echo -e "${GREEN}✓${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            echo -e "${RED}✗${NC} (Expected: '$expected_result', Got: '$result')"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    else
        if [ "$result" != "FAILED" ] && [ -n "$result" ]; then
            echo -e "${GREEN}✓${NC}"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        else
            echo -e "${RED}✗${NC}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            return 1
        fi
    fi
}

echo "=== Comprehensive VDO.Ninja Intercom Test ==="
if [ -n "$SSH_HOST" ]; then
    echo "Target: $SSH_HOST"
else
    echo "Target: Local"
fi
echo ""

# 1. SERVICE STATUS TESTS
echo "1. SERVICE STATUS CHECKS:"
run_test "Service is enabled" "systemctl is-enabled $SERVICE 2>/dev/null" "enabled"
run_test "Service is active" "systemctl is-active $SERVICE 2>/dev/null" "active"
run_test "Service hasn't failed recently" "systemctl show $SERVICE --property=NRestarts --value | awk '{if(\$1<3) print \"OK\"; else print \"FAILED\"}'" "OK"

# 2. PROCESS CHECKS
echo ""
echo "2. PROCESS CHECKS:"
run_test "Chrome main process running" "pgrep -f 'chrome --no' >/dev/null && echo 'OK'" "OK"
run_test "Xvfb display running" "pgrep -f 'Xvfb :99' >/dev/null && echo 'OK'" "OK"
run_test "VNC server running" "pgrep -f 'x11vnc.*5999' >/dev/null && echo 'OK'" "OK"
run_test "PipeWire running" "pgrep -x pipewire >/dev/null && echo 'OK'" "OK"
run_test "PipeWire-pulse running" "pgrep -x pipewire-pulse >/dev/null && echo 'OK'" "OK"
run_test "WirePlumber running" "pgrep -x wireplumber >/dev/null && echo 'OK'" "OK"

# 3. AUDIO CONFIGURATION
echo ""
echo "3. AUDIO CONFIGURATION:"
run_test "PulseAudio socket exists" "[ -S /run/user/0/pulse/native ] && echo 'OK'" "OK"
run_test "USB Audio device detected in ALSA" "aplay -l 2>/dev/null | grep -q 'USB Audio' && echo 'OK'" "OK"
run_test "USB Audio in PipeWire sinks" "pactl list sinks short 2>/dev/null | grep -q USB && echo 'OK'" "OK"
run_test "USB Audio in PipeWire sources" "pactl list sources short 2>/dev/null | grep -q USB && echo 'OK'" "OK"
run_test "USB Audio is default sink" "pactl info 2>/dev/null | grep 'Default Sink:' | grep -q usb && echo 'OK'" "OK"
run_test "USB Audio is default source" "pactl info 2>/dev/null | grep 'Default Source:' | grep -q usb && echo 'OK'" "OK"

# 4. CHROME CONFIGURATION
echo ""
echo "4. CHROME CONFIGURATION:"
chrome_url=$(run_command "ps aux | grep chrome | grep vdo | head -1 | grep -o 'https://vdo.ninja[^ ]*'" 2>/dev/null || echo "")
if [ -n "$chrome_url" ]; then
    run_test "Chrome has VDO.Ninja URL" "echo '$chrome_url' | grep -q 'vdo.ninja' && echo 'OK'" "OK"
    run_test "Room parameter correct" "echo '$chrome_url' | grep -q 'room=$EXPECTED_ROOM' && echo 'OK'" "OK"
    run_test "Push parameter present" "echo '$chrome_url' | grep -q '&push=' && echo 'OK'" "OK"
    run_test "Miconly parameter present" "echo '$chrome_url' | grep -q '&miconly' && echo 'OK'" "OK"
    run_test "Autostart parameter present" "echo '$chrome_url' | grep -q '&autostart' && echo 'OK'" "OK"
    run_test "Audio device parameter present" "echo '$chrome_url' | grep -q '&aid=' && echo 'OK'" "OK"
    run_test "No webcam parameter" "echo '$chrome_url' | grep -v '&webcam' >/dev/null && echo 'OK'" "OK"
    run_test "No video device parameter" "echo '$chrome_url' | grep -v '&videodevice=' >/dev/null && echo 'OK'" "OK"
else
    echo -e "  ${RED}✗${NC} Chrome URL not found"
    TESTS_FAILED=$((TESTS_FAILED + 8))
    TESTS_RUN=$((TESTS_RUN + 8))
fi

# 5. CHROME ENVIRONMENT
echo ""
echo "5. CHROME ENVIRONMENT:"
chrome_pid=$(run_command "pgrep -f 'chrome --no' | head -1" 2>/dev/null || echo "")
if [ -n "$chrome_pid" ]; then
    run_test "PULSE_SERVER set" "cat /proc/$chrome_pid/environ 2>/dev/null | tr '\0' '\n' | grep -q '^PULSE_SERVER=' && echo 'OK'" "OK"
    run_test "PULSE_RUNTIME_PATH set" "cat /proc/$chrome_pid/environ 2>/dev/null | tr '\0' '\n' | grep -q '^PULSE_RUNTIME_PATH=' && echo 'OK'" "OK"
    run_test "XDG_RUNTIME_DIR set" "cat /proc/$chrome_pid/environ 2>/dev/null | tr '\0' '\n' | grep -q '^XDG_RUNTIME_DIR=' && echo 'OK'" "OK"
else
    echo -e "  ${RED}✗${NC} Chrome PID not found"
    TESTS_FAILED=$((TESTS_FAILED + 3))
    TESTS_RUN=$((TESTS_RUN + 3))
fi

# 6. CHROME AUDIO STREAM
echo ""
echo "6. CHROME AUDIO STREAM:"
run_test "No audio stream errors in last 60s" "journalctl -u $SERVICE --since '1 minute ago' 2>/dev/null | grep -c 'Failed to open stream' | awk '{if(\$1==0) print \"OK\"; else print \"FAILED\"}'" "OK"
run_test "Chrome connected to PulseAudio" "lsof -p \$(pgrep -f 'chrome --no' | head -1) 2>/dev/null | grep -q 'pulse/native' && echo 'OK'" "OK"

# 7. VNC ACCESS
echo ""
echo "7. VNC ACCESS:"
run_test "VNC port 5999 listening" "netstat -tln 2>/dev/null | grep -q ':5999' && echo 'OK'" "OK"

# 8. SERVICE LOGS
echo ""
echo "8. SERVICE LOG VERIFICATION:"
run_test "Service started successfully" "journalctl -u $SERVICE -n 100 --no-pager 2>/dev/null | grep -q 'Starting Chrome...' && echo 'OK'" "OK"
run_test "USB Audio detected in logs" "journalctl -u $SERVICE -n 100 --no-pager 2>/dev/null | grep -q 'USB Audio' && echo 'OK'" "OK"
run_test "Default audio set in logs" "journalctl -u $SERVICE -n 100 --no-pager 2>/dev/null | grep -q 'Default.*set to.*usb' && echo 'OK'" "OK"
run_test "PipeWire started in logs" "journalctl -u $SERVICE -n 100 --no-pager 2>/dev/null | grep -q 'PipeWire.*ready' && echo 'OK'" "OK"

# SUMMARY
echo ""
echo "========================================="
echo "TEST SUMMARY:"
echo "  Tests Run:    $TESTS_RUN"
echo -e "  Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "  Tests Failed: ${RED}$TESTS_FAILED${NC}"
else
    echo -e "  Tests Failed: $TESTS_FAILED"
fi

success_rate=$((TESTS_PASSED * 100 / TESTS_RUN))
echo ""
echo -n "Success Rate: "
if [ $success_rate -eq 100 ]; then
    echo -e "${GREEN}${success_rate}%${NC} - PERFECT!"
    exit 0
elif [ $success_rate -ge 90 ]; then
    echo -e "${GREEN}${success_rate}%${NC} - Very Good"
    exit 0
elif [ $success_rate -ge 70 ]; then
    echo -e "${YELLOW}${success_rate}%${NC} - Needs Improvement"
    exit 1
else
    echo -e "${RED}${success_rate}%${NC} - Critical Issues"
    exit 1
fi