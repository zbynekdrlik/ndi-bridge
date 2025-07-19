#!/bin/bash
# Test different formats and resolutions to find what works at 60fps

set -e

echo "🎥 Testing different capture formats for 60fps"
echo "============================================="

# Ensure we're in the right directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/build/bin"

# Test function
test_format() {
    local res="$1"
    local name="$2"
    
    echo ""
    echo "Testing: $name"
    echo "------------------------"
    
    # Run for 5 seconds and capture output
    timeout 5s ./ndi-bridge /dev/video0 "TEST-$name" 2>&1 | grep -E "(Set format|Actual FPS|Overall FPS|frame gap)" | tail -20
    
    echo "------------------------"
    sleep 2
}

# Make sure capabilities are set
sudo setcap 'cap_sys_nice,cap_ipc_lock+ep' ./ndi-bridge

echo ""
echo "📊 Running format tests (5 seconds each)..."

# Test 720p first (should have better chance at 60fps)
echo ""
echo "🔹 Testing 720p60 (lower bandwidth requirement)"
test_format "1280x720" "720p60"

# Test 1080p again to compare
echo ""
echo "🔹 Testing 1080p60 (current problematic setting)"
test_format "1920x1080" "1080p60"

# Test lower resolutions
echo ""
echo "🔹 Testing 480p60 (minimal bandwidth)"
test_format "640x480" "480p60"

echo ""
echo "✅ Format testing complete!"
echo ""
echo "RECOMMENDATIONS:"
echo "- If 720p60 works but 1080p60 doesn't: USB bandwidth issue"
echo "- If all fail at 60fps: Device limitation"
echo "- Check USB port (USB 2.0 vs 3.0)"
