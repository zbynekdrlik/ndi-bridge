#!/bin/bash
# Final test runner after image build
# Ensures all fixes are properly applied and working

set -e

echo "================================"
echo "Final Test Verification"
echo "================================"
echo "Date: $(date)"
echo ""

# Check if image exists
if [ ! -f "ndi-bridge.img" ]; then
    echo "ERROR: ndi-bridge.img not found!"
    echo "Please wait for build to complete first."
    exit 1
fi

# Export required test variables
export TEST_BOX_IP=10.77.9.143

# Run complete test suite
echo "Starting complete integration test suite..."
echo "This will:"
echo "1. Deploy the new image to the box"
echo "2. Run all functional tests"
echo "3. Verify all fixes are working"
echo ""

# Run the complete test
./tests/integration/test_complete.sh ndi-bridge.img false

# Check result
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ ALL TESTS PASSED!"
    echo "The image is ready for production use."
else
    echo ""
    echo "❌ Some tests failed."
    echo "Please review the test logs in tests/logs/"
fi