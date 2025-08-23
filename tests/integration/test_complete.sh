#!/bin/bash
# Complete integration test
# Runs deployment and ALL functionality tests in sequence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"  
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
IMAGE_FILE="${1:-ndi-bridge.img}"
SKIP_DEPLOYMENT="${2:-false}"

# Track overall results
SUITE_RESULTS=()
SUITE_PASSED=0
SUITE_FAILED=0
START_TIME=$(date +%s)

echo "================================"
echo "Complete NDI Bridge Integration Test"
echo "================================"
echo "Target box: $TEST_BOX_IP"
echo "Image: $IMAGE_FILE"
echo "Skip deployment: $SKIP_DEPLOYMENT"
echo "Date: $(date)"
echo ""

# Initialize logs
setup_test_logs
INTEGRATION_LOG="${TEST_LOG_DIR}/integration_$(date +%Y%m%d_%H%M%S).log"

# Function to run a test suite
run_suite() {
    local suite_name="$1"
    local suite_script="$2"
    local suite_start=$(date +%s)
    
    echo "--------------------------------"
    echo "Running: $suite_name"
    echo "--------------------------------"
    
    if [ ! -f "$suite_script" ]; then
        echo "❌ Test script not found: $suite_script"
        SUITE_RESULTS+=("$suite_name:SKIP:Script not found")
        return 1
    fi
    
    # Make executable
    chmod +x "$suite_script"
    
    # Run the test and capture output
    if "$suite_script" >> "$INTEGRATION_LOG" 2>&1; then
        local suite_end=$(date +%s)
        local duration=$((suite_end - suite_start))
        echo "✅ $suite_name completed in ${duration}s"
        SUITE_RESULTS+=("$suite_name:PASS:${duration}s")
        SUITE_PASSED=$((SUITE_PASSED + 1))
        return 0
    else
        local suite_end=$(date +%s)
        local duration=$((suite_end - suite_start))
        echo "❌ $suite_name failed after ${duration}s"
        SUITE_RESULTS+=("$suite_name:FAIL:${duration}s")
        SUITE_FAILED=$((SUITE_FAILED + 1))
        
        # Show last few lines of error
        echo "Last error output:"
        tail -10 "$INTEGRATION_LOG" | grep -E "ERROR|FAIL" | tail -3
        return 1
    fi
}

# Check connectivity first
echo "Checking connectivity to test box..."
if ! box_ping; then
    echo "❌ Cannot reach box at $TEST_BOX_IP"
    exit 1
fi
echo "✅ Box is reachable"
echo ""

# Step 1: Deployment (if not skipped)
if [ "$SKIP_DEPLOYMENT" != "true" ]; then
    if [ ! -f "$IMAGE_FILE" ]; then
        echo "❌ Image file not found: $IMAGE_FILE"
        echo "Build an image first with: sudo ./build-image-for-rufus.sh"
        exit 1
    fi
    
    run_suite "Deployment & Reboot Test" "${SCRIPT_DIR}/test_full_deployment.sh"
    
    # If deployment failed, stop here
    if [ $? -ne 0 ]; then
        echo ""
        echo "❌ Deployment failed - cannot continue with other tests"
        exit 1
    fi
    
    echo ""
    echo "Waiting for services to stabilize after deployment..."
    sleep 10
else
    echo "Skipping deployment test (SKIP_DEPLOYMENT=true)"
    echo ""
fi

# Step 2: Core functionality tests
echo "Running core functionality tests..."
echo ""

# Capture test (most critical)
run_suite "Capture Test" "${SCRIPT_DIR}/test_capture.sh"

# Network test (foundation for everything)
run_suite "Network Test" "${SCRIPT_DIR}/test_network.sh"

# Time sync test (important for quality)
run_suite "Time Sync Test" "${SCRIPT_DIR}/test_timesync.sh"

# Helper scripts test
run_suite "Helper Scripts Test" "${SCRIPT_DIR}/test_helpers.sh"

# Step 3: Service tests
echo ""
echo "Running service tests..."
echo ""

# Display test
run_suite "Display Test" "${SCRIPT_DIR}/test_display.sh"

# Audio test
run_suite "Audio Test" "${SCRIPT_DIR}/test_audio.sh"

# Web interface test
run_suite "Web Interface Test" "${SCRIPT_DIR}/test_web.sh"

# Step 4: Cleanup
echo ""
echo "Cleaning up test environment..."
box_cleanup_all >> "$INTEGRATION_LOG" 2>&1

# Step 5: Final verification
echo ""
echo "Final verification..."

# Check critical services are still running
final_checks_passed=true

echo -n "  Checking ndi-bridge service... "
if box_service_status "ndi-bridge" | grep -q "active"; then
    echo "✅ Active"
else
    echo "❌ Not active"
    final_checks_passed=false
fi

echo -n "  Checking capture state... "
capture_state=$(box_ssh "cat /var/run/ndi-bridge/capture_state 2>/dev/null" | tr -d '\n')
if [ -n "$capture_state" ] && [ "$capture_state" != "STOPPED" ]; then
    echo "✅ $capture_state"
else
    echo "❌ Not capturing"
    final_checks_passed=false
fi

echo -n "  Checking time sync... "
if assert_time_synchronized 2>/dev/null; then
    echo "✅ Synchronized"
else
    echo "⚠️  Not synchronized"
fi

echo -n "  Checking network... "
if box_check_network 2>/dev/null; then
    echo "✅ Connected"
else
    echo "❌ No network"
    final_checks_passed=false
fi

# Calculate totals
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Print final summary
echo ""
echo "================================"
echo "Integration Test Summary"
echo "================================"
echo "Total Duration: ${TOTAL_DURATION}s ($(($TOTAL_DURATION / 60))m $(($TOTAL_DURATION % 60))s)"
echo ""
echo "Test Suite Results:"
for result in "${SUITE_RESULTS[@]}"; do
    IFS=':' read -r suite status duration <<< "$result"
    if [ "$status" = "PASS" ]; then
        echo "  ✅ $suite - PASSED ($duration)"
    elif [ "$status" = "FAIL" ]; then
        echo "  ❌ $suite - FAILED ($duration)"
    else
        echo "  ⏩ $suite - SKIPPED"
    fi
done

echo ""
echo "Overall: $SUITE_PASSED passed, $SUITE_FAILED failed"
echo ""

# Determine exit status
if [ $SUITE_FAILED -eq 0 ] && [ "$final_checks_passed" = "true" ]; then
    echo "✅ COMPLETE INTEGRATION TEST PASSED!"
    echo ""
    echo "The NDI Bridge box is fully functional:"
    echo "  - Image deployed and box rebooted successfully"
    echo "  - All services running correctly"
    echo "  - Capture working at expected FPS"
    echo "  - Display assignment and removal working"
    echo "  - Audio output functional"
    echo "  - Network and web interface operational"
    echo "  - Time synchronization active"
    echo "  - All helper scripts functional"
    echo ""
    echo "Full logs available at: $INTEGRATION_LOG"
    exit 0
else
    echo "❌ INTEGRATION TEST FAILED"
    echo ""
    if [ $SUITE_FAILED -gt 0 ]; then
        echo "$SUITE_FAILED test suite(s) failed - check logs for details"
    fi
    if [ "$final_checks_passed" != "true" ]; then
        echo "Final verification checks failed - box may be in unstable state"
    fi
    echo ""
    echo "Full logs available at: $INTEGRATION_LOG"
    echo "Review failed tests and fix issues before deployment"
    exit 1
fi