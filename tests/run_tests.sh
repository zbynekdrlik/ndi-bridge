#!/bin/bash
# Master test runner for NDI Bridge
# Runs all test suites and generates comprehensive report

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/ro_check.sh"

# Test runner configuration
TEST_SUITES=()
TEST_SUITE_RESULTS=()
TOTAL_PASSED=0
TOTAL_FAILED=0
START_TIME=$(date +%s)

# Parse command line arguments
RUN_DEPLOYMENT=false
RUN_CAPTURE=true
RUN_DISPLAY=true
RUN_AUDIO=true
RUN_NETWORK=false
RUN_WEB=false
RUN_TIMESYNC=false
RUN_HELPERS=false
RUN_INTERCOM=false
RUN_LONG_TESTS=false
RUN_COMPLETE=false
TEST_BOX_IP=""

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Run automated tests for NDI Bridge

Options:
    -h, --help          Show this help message
    -i, --ip ADDRESS    IP address of test box (required)
    -a, --all           Run all tests including deployment
    --complete          Run complete integration test (deployment + all)
    -d, --deployment    Include deployment test (requires image file)
    -c, --capture       Run capture tests (default: yes)
    -s, --display       Run display tests (default: yes)
    -u, --audio         Run audio tests (default: yes)
    -n, --network       Run network tests (default: no)
    -w, --web           Run web interface tests (default: no)
    -t, --timesync      Run time sync tests (default: no)
    -e, --helpers       Run helper scripts tests (default: no)
    -m, --intercom      Run intercom tests (default: no)
    -l, --long          Run long-duration tests
    --skip-capture      Skip capture tests
    --skip-display      Skip display tests
    --skip-audio        Skip audio tests
    -q, --quick         Quick test (capture only)

Examples:
    # Run all standard tests
    $0 -i 10.77.9.143
    
    # Run deployment and all tests
    $0 -i 10.77.9.143 --all
    
    # Quick capture-only test
    $0 -i 10.77.9.143 --quick
    
    # Run with long-duration tests
    $0 -i 10.77.9.143 --long

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -i|--ip)
            TEST_BOX_IP="$2"
            shift 2
            ;;
        -a|--all)
            RUN_DEPLOYMENT=true
            RUN_NETWORK=true
            RUN_TIMESYNC=true
            RUN_HELPERS=true
            RUN_WEB=true
            shift
            ;;
        -d|--deployment)
            RUN_DEPLOYMENT=true
            shift
            ;;
        -c|--capture)
            RUN_CAPTURE=true
            shift
            ;;
        -s|--display)
            RUN_DISPLAY=true
            shift
            ;;
        -u|--audio)
            RUN_AUDIO=true
            shift
            ;;
        -n|--network)
            RUN_NETWORK=true
            shift
            ;;
        -w|--web)
            RUN_WEB=true
            shift
            ;;
        -t|--timesync)
            RUN_TIMESYNC=true
            shift
            ;;
        -e|--helpers)
            RUN_HELPERS=true
            shift
            ;;
        -m|--intercom)
            RUN_INTERCOM=true
            shift
            ;;
        --complete)
            RUN_COMPLETE=true
            shift
            ;;
        -l|--long)
            RUN_LONG_TESTS=true
            shift
            ;;
        --skip-capture)
            RUN_CAPTURE=false
            shift
            ;;
        --skip-display)
            RUN_DISPLAY=false
            shift
            ;;
        --skip-audio)
            RUN_AUDIO=false
            shift
            ;;
        -q|--quick)
            RUN_CAPTURE=true
            RUN_DISPLAY=false
            RUN_AUDIO=false
            RUN_DEPLOYMENT=false
            RUN_NETWORK=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h for help"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$TEST_BOX_IP" ]; then
    echo "Error: Test box IP address is required"
    echo "Use -i or --ip to specify the IP address"
    echo ""
    usage
fi

# Export configuration
export TEST_BOX_IP
export RUN_LONG_TESTS

# Initialize test environment
setup_test_logs

# Check if running complete integration test
if [ "$RUN_COMPLETE" = "true" ]; then
    echo "================================"
    echo "Running Complete Integration Test"
    echo "================================"
    echo "This will run deployment and ALL tests"
    echo ""
    
    # Run the complete integration test
    chmod +x "${SCRIPT_DIR}/integration/test_complete.sh"
    "${SCRIPT_DIR}/integration/test_complete.sh"
    exit $?
fi

echo "================================"
echo "NDI Bridge Automated Test Suite"
echo "================================"
echo "Test box: $TEST_BOX_IP"
echo "Date: $(date)"
echo "Log file: $TEST_LOG_FILE"
echo ""

# Check connectivity
log_info "Checking connectivity to test box..."
if ! ping -c 1 -W 2 "$TEST_BOX_IP" &>/dev/null; then
    log_error "Cannot reach test box at $TEST_BOX_IP"
    exit 1
fi
log_info "Test box is reachable"

# CRITICAL: Verify filesystem is read-only
log_info "Verifying filesystem status..."
if ! verify_readonly_filesystem "$TEST_BOX_IP"; then
    log_error "Filesystem verification failed - tests cannot proceed"
    echo ""
    echo "This is a critical requirement for test validity."
    echo "Tests must run against a read-only filesystem to ensure"
    echo "they reflect real production conditions."
    exit 1
fi
log_info "Filesystem verified as read-only ✓"

# Get system information
log_info "Getting system information..."
# Source the box control and assertions libraries
source "${SCRIPT_DIR}/lib/assertions.sh"
source "${SCRIPT_DIR}/lib/box_control.sh"
system_info=$(box_get_system_info 2>/dev/null || echo "Could not get system info")
echo "$system_info"
echo ""

# Function to run a test suite
run_test_suite() {
    local test_name="$1"
    local test_script="$2"
    local suite_start=$(date +%s)
    
    echo "--------------------------------"
    echo "Running: $test_name"
    echo "--------------------------------"
    
    if [ ! -f "$test_script" ]; then
        log_error "Test script not found: $test_script"
        TEST_SUITE_RESULTS+=("$test_name:SKIP:Script not found")
        return 1
    fi
    
    # Make script executable
    chmod +x "$test_script"
    
    # Run the test
    if "$test_script"; then
        local suite_end=$(date +%s)
        local duration=$((suite_end - suite_start))
        log_info "$test_name completed in ${duration}s"
        TEST_SUITE_RESULTS+=("$test_name:PASS:${duration}s")
        return 0
    else
        local suite_end=$(date +%s)
        local duration=$((suite_end - suite_start))
        log_error "$test_name failed after ${duration}s"
        TEST_SUITE_RESULTS+=("$test_name:FAIL:${duration}s")
        return 1
    fi
}

# Run deployment test if requested
if [ "$RUN_DEPLOYMENT" = "true" ]; then
    if [ -f "ndi-bridge.img" ]; then
        run_test_suite "Deployment Test" "${SCRIPT_DIR}/integration/test_full_deployment.sh"
    else
        log_warn "Skipping deployment test - no image file found"
        log_warn "Build an image first with: sudo ./build-image-for-rufus.sh"
    fi
fi

# Run capture tests
if [ "$RUN_CAPTURE" = "true" ]; then
    run_test_suite "Capture Test" "${SCRIPT_DIR}/integration/test_capture.sh"
fi

# Run display tests
if [ "$RUN_DISPLAY" = "true" ]; then
    run_test_suite "Display Test" "${SCRIPT_DIR}/integration/test_display.sh"
fi

# Run audio tests
if [ "$RUN_AUDIO" = "true" ]; then
    run_test_suite "Audio Test" "${SCRIPT_DIR}/integration/test_audio.sh"
fi

# Run network tests if requested
if [ "$RUN_NETWORK" = "true" ]; then
    run_test_suite "Network Test" "${SCRIPT_DIR}/integration/test_network.sh"
fi

# Run web interface tests if requested
if [ "$RUN_WEB" = "true" ]; then
    run_test_suite "Web Interface Test" "${SCRIPT_DIR}/integration/test_web.sh"
fi

# Run time sync tests if requested
if [ "$RUN_TIMESYNC" = "true" ]; then
    run_test_suite "Time Sync Test" "${SCRIPT_DIR}/integration/test_timesync.sh"
fi

# Run helper scripts tests if requested
if [ "$RUN_HELPERS" = "true" ]; then
    run_test_suite "Helper Scripts Test" "${SCRIPT_DIR}/integration/test_helpers.sh"
fi

# Run VDO.Ninja intercom tests
if [ "$RUN_INTERCOM" = "true" ]; then
    run_test_suite "VDO.Ninja Intercom Test" "${SCRIPT_DIR}/integration/test_vdo_intercom.sh"
fi

# Calculate totals
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Print summary
echo ""
echo "================================"
echo "Test Suite Summary"
echo "================================"
echo "Total Duration: ${TOTAL_DURATION}s"
echo ""
echo "Suite Results:"
for result in "${TEST_SUITE_RESULTS[@]}"; do
    IFS=':' read -r suite status duration <<< "$result"
    if [ "$status" = "PASS" ]; then
        echo "  ✅ $suite - PASSED ($duration)"
        TOTAL_PASSED=$((TOTAL_PASSED + 1))
    elif [ "$status" = "FAIL" ]; then
        echo "  ❌ $suite - FAILED ($duration)"
        TOTAL_FAILED=$((TOTAL_FAILED + 1))
    else
        echo "  ⏩ $suite - SKIPPED ($duration)"
    fi
done

echo ""
echo "Total: $TOTAL_PASSED passed, $TOTAL_FAILED failed"

# Generate detailed report
REPORT_FILE="${TEST_LOG_DIR}/test_report_$(date +%Y%m%d_%H%M%S).txt"
cat > "$REPORT_FILE" << EOF
NDI Bridge Test Report
======================
Date: $(date)
Test Box: $TEST_BOX_IP
Duration: ${TOTAL_DURATION}s

Configuration:
- Deployment Test: $RUN_DEPLOYMENT
- Capture Test: $RUN_CAPTURE
- Display Test: $RUN_DISPLAY
- Audio Test: $RUN_AUDIO
- Network Test: $RUN_NETWORK
- Long Tests: $RUN_LONG_TESTS

Results Summary:
- Passed: $TOTAL_PASSED
- Failed: $TOTAL_FAILED

Detailed Results:
EOF

for result in "${TEST_SUITE_RESULTS[@]}"; do
    echo "$result" >> "$REPORT_FILE"
done

echo ""
echo "Detailed report saved to: $REPORT_FILE"
echo "Full logs available at: $TEST_LOG_FILE"

# Exit with appropriate code
if [ $TOTAL_FAILED -eq 0 ]; then
    echo ""
    echo "✅ All test suites passed successfully!"
    exit 0
else
    echo ""
    echo "❌ $TOTAL_FAILED test suite(s) failed"
    exit 1
fi