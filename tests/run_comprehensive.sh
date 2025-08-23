#!/bin/bash
# Comprehensive test suite for NDI Bridge
# Runs all validated tests in sequence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Check for required IP parameter
if [ -z "$1" ]; then
    echo "Usage: $0 <box-ip>"
    echo "Example: $0 10.77.9.140"
    exit 1
fi

export TEST_BOX_IP="$1"
FAILED_TESTS=()
PASSED_TESTS=()
START_TIME=$(date +%s)

echo ""
echo "================================"
echo "NDI Bridge Comprehensive Test Suite"
echo "================================"
echo "Target box: $TEST_BOX_IP"
echo "Date: $(date)"
echo ""

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_script="$2"
    local allow_fail="${3:-false}"
    
    echo "--------------------------------"
    echo "Running: $test_name"
    echo "--------------------------------"
    
    if "${SCRIPT_DIR}/$test_script" 2>&1 | tee "/tmp/test_${test_name// /_}.log"; then
        echo "✅ $test_name PASSED"
        PASSED_TESTS+=("$test_name")
    else
        if [ "$allow_fail" = "true" ]; then
            echo "⚠️  $test_name FAILED (non-critical)"
        else
            echo "❌ $test_name FAILED"
            FAILED_TESTS+=("$test_name")
        fi
    fi
    echo ""
}

# Phase 1: Deployment and Reboot
echo "=== Phase 1: Deployment and System Verification ==="
run_test "Full Deployment with Reboot" "integration/test_full_deployment.sh"

# Give system time to stabilize after deployment
echo "Waiting for system to stabilize..."
sleep 10

# Phase 2: Core Functionality
echo ""
echo "=== Phase 2: Core Functionality Tests ==="
run_test "Basic Functionality" "integration/test_basic.sh"
run_test "Capture Functionality" "integration/test_capture.sh"

# Phase 3: Network (allow failures for external dependencies)
echo ""
echo "=== Phase 3: Network Tests ==="
run_test "Network Configuration" "integration/test_network.sh" true

# Phase 4: Services (allow failures for optional services)
echo ""
echo "=== Phase 4: Service Tests ==="
run_test "Helper Scripts" "integration/test_helpers.sh" true
run_test "Web Interface" "integration/test_web.sh" true

# Phase 5: Display Tests (simplified version)
echo ""
echo "=== Phase 5: Display Tests ==="
if [ -f "${SCRIPT_DIR}/integration/test_display_simple.sh" ]; then
    run_test "Display Functionality (Simplified)" "integration/test_display_simple.sh"
else
    run_test "Display Functionality" "integration/test_display.sh" true
fi

# Calculate test duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

# Print summary
echo ""
echo "================================"
echo "Test Suite Summary"
echo "================================"
echo "Duration: ${MINUTES}m ${SECONDS}s"
echo ""
echo "Passed Tests (${#PASSED_TESTS[@]}):"
for test in "${PASSED_TESTS[@]}"; do
    echo "  ✅ $test"
done

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo ""
    echo "Failed Tests (${#FAILED_TESTS[@]}):"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  ❌ $test"
    done
fi

echo ""
echo "--------------------------------"
if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo "🎉 ALL CRITICAL TESTS PASSED!"
    echo "================================"
    exit 0
else
    echo "⚠️  ${#FAILED_TESTS[@]} CRITICAL TEST(S) FAILED"
    echo "================================"
    exit 1
fi