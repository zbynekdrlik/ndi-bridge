#!/bin/bash
# Quick test runner - runs only essential tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================"
echo "NDI Bridge Quick Test"
echo "================================"
echo ""
echo "This will run a quick capture test to verify basic functionality."
echo "Full test suite: ./run_tests.sh -i <IP>"
echo ""

# Check if IP provided
if [ -z "$1" ]; then
    echo "Usage: $0 <box-ip>"
    echo "Example: $0 10.77.9.143"
    exit 1
fi

# Run quick test with 60 second timeout
echo "Running quick test on $1 (timeout: 60s)..."
timeout 60 "${SCRIPT_DIR}/run_tests.sh" -i "$1" --quick

exit_code=$?
if [ $exit_code -eq 124 ]; then
    echo ""
    echo "⚠️  Test timed out after 60 seconds"
    echo "The box may be slow or unresponsive"
    exit 1
elif [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ Quick test passed!"
    exit 0
else
    echo ""
    echo "❌ Quick test failed (exit code: $exit_code)"
    exit $exit_code
fi