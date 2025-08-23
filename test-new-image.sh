#!/bin/bash
# Test newly built image on box without USB flashing
# This replaces the manual USB burn/deploy process

set -e

# Configuration
BOX_IP="${1:-10.77.9.140}"
IMAGE_FILE="${2:-ndi-bridge.img}"

echo "================================"
echo "NDI Bridge Image Test Deployment"
echo "================================"
echo "Box IP: $BOX_IP"
echo "Image: $IMAGE_FILE"
echo ""

# Check prerequisites
if [ ! -f "$IMAGE_FILE" ]; then
    echo "❌ Error: Image file '$IMAGE_FILE' not found"
    echo "Build an image first with: sudo ./build-image-for-rufus.sh"
    exit 1
fi

# Check if sshpass is installed
if ! command -v sshpass &> /dev/null; then
    echo "❌ Error: sshpass is required but not installed"
    echo "Install with: sudo apt-get install sshpass"
    exit 1
fi

# Test connectivity
echo "Checking connectivity to box..."
if ! ping -c 1 -W 2 "$BOX_IP" &>/dev/null; then
    echo "❌ Error: Cannot reach box at $BOX_IP"
    exit 1
fi
echo "✅ Box is reachable"

# Deploy the image
echo ""
echo "Deploying image to box (this takes 1-2 minutes)..."
./deploy-to-box.sh "$BOX_IP" "$IMAGE_FILE"

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi

echo "✅ Image deployed successfully"

# Wait for services to stabilize
echo ""
echo "Waiting for services to start..."
sleep 10

# Run quick test
echo ""
echo "Running quick test to verify deployment..."
./tests/quick-test.sh "$BOX_IP"

if [ $? -eq 0 ]; then
    echo ""
    echo "================================"
    echo "✅ SUCCESS: Image tested and working!"
    echo "================================"
    echo ""
    echo "Next steps:"
    echo "1. Run full test suite: ./tests/run_tests.sh -i $BOX_IP"
    echo "2. Test audio: ./tests/run_tests.sh -i $BOX_IP -u"
    echo "3. Test display: ./tests/run_tests.sh -i $BOX_IP -s"
    exit 0
else
    echo ""
    echo "================================"
    echo "❌ FAILED: Image has issues"
    echo "================================"
    echo "Check logs in tests/logs/"
    exit 1
fi