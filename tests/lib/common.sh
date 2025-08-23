#!/bin/bash
# Common functions for all tests

# Source configuration
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIB_DIR}/../fixtures/test_config.env"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# SSH execution wrapper
box_ssh() {
    local cmd="$1"
    sshpass -p "$TEST_BOX_PASS" ssh $TEST_BOX_SSH_OPTS \
        "${TEST_BOX_USER}@${TEST_BOX_IP}" "$cmd" 2>/dev/null
}

# SCP wrapper
box_scp() {
    local src="$1"
    local dest="$2"
    sshpass -p "$TEST_BOX_PASS" scp $TEST_BOX_SSH_OPTS \
        "$src" "${TEST_BOX_USER}@${TEST_BOX_IP}:$dest" 2>/dev/null
}

# Check if box is reachable
box_ping() {
    ping -c 1 -W 2 "$TEST_BOX_IP" &>/dev/null
}

# Wait for box to be reachable
box_wait_online() {
    local timeout="${1:-60}"
    local count=0
    
    log_info "Waiting for box at $TEST_BOX_IP to come online..."
    while ! box_ping; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $timeout ]; then
            log_error "Timeout waiting for box to come online"
            return 1
        fi
        echo -n "."
    done
    echo ""
    log_info "Box is online"
    
    # Wait a bit more for SSH to be ready
    sleep 5
    return 0
}

# Get service status
box_service_status() {
    local service="$1"
    box_ssh "systemctl is-active $service" | tr -d '\n'
}

# Get status file content
box_get_status_file() {
    local file="$1"
    box_ssh "cat $file 2>/dev/null"
}

# Parse status file value
parse_status_value() {
    local content="$1"
    local key="$2"
    echo "$content" | grep "^${key}=" | cut -d'=' -f2 | tr -d '"'
}

# Check if process is running
box_process_running() {
    local process="$1"
    box_ssh "pgrep -f '$process' > /dev/null && echo 'running' || echo 'stopped'" | tr -d '\n'
}

# Get NDI display status
box_get_display_status() {
    local display_id="${1:-1}"
    box_get_status_file "/var/run/ndi-display/display-${display_id}.status"
}

# Get capture status
box_get_capture_status() {
    # Build status from individual files
    local fps=$(box_ssh "cat /var/run/ndi-bridge/fps_current 2>/dev/null | tr -d '\n'")
    local state=$(box_ssh "cat /var/run/ndi-bridge/capture_state 2>/dev/null | tr -d '\n'")
    local frames=$(box_ssh "cat /var/run/ndi-bridge/frames_total 2>/dev/null | tr -d '\n'")
    local dropped=$(box_ssh "cat /var/run/ndi-bridge/frames_dropped 2>/dev/null | tr -d '\n'")
    
    # Return in status file format
    if [ -n "$state" ]; then
        echo "CAPTURE_STATE=$state"
        echo "CURRENT_FPS=$fps"
        echo "TOTAL_FRAMES=$frames"
        echo "DROPPED_FRAMES=$dropped"
        echo "RESOLUTION=1920x1080"
    fi
}

# Create test log directory
setup_test_logs() {
    mkdir -p "$TEST_LOG_DIR"
    TEST_LOG_FILE="${TEST_LOG_DIR}/test_$(date +%Y%m%d_%H%M%S).log"
    export TEST_LOG_FILE
}

# Save command output to log
log_output() {
    local label="$1"
    local output="$2"
    if [ -n "$TEST_LOG_FILE" ]; then
        echo "=== $label ===" >> "$TEST_LOG_FILE"
        echo "$output" >> "$TEST_LOG_FILE"
        echo "" >> "$TEST_LOG_FILE"
    fi
}

# Test result tracking
TEST_RESULTS=()
TEST_PASSED=0
TEST_FAILED=0

# Record test result
record_test() {
    local test_name="$1"
    local result="$2"  # PASS or FAIL
    local message="${3:-}"
    
    TEST_RESULTS+=("${test_name}:${result}:${message}")
    
    if [ "$result" = "PASS" ]; then
        TEST_PASSED=$((TEST_PASSED + 1))
        log_info "✓ $test_name"
    else
        TEST_FAILED=$((TEST_FAILED + 1))
        log_error "✗ $test_name: $message"
    fi
}

# Print test summary
print_test_summary() {
    echo ""
    echo "================================"
    echo "Test Summary"
    echo "================================"
    echo "Passed: $TEST_PASSED"
    echo "Failed: $TEST_FAILED"
    echo "Total:  $((TEST_PASSED + TEST_FAILED))"
    echo ""
    
    if [ $TEST_FAILED -gt 0 ]; then
        echo "Failed Tests:"
        for result in "${TEST_RESULTS[@]}"; do
            IFS=':' read -r name status msg <<< "$result"
            if [ "$status" = "FAIL" ]; then
                echo "  - $name: $msg"
            fi
        done
        return 1
    fi
    return 0
}