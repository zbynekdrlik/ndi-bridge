#!/bin/bash
# Diagnose HDMI capture device capabilities

echo "🔍 HDMI Capture Device Diagnostics"
echo "===================================="

# Check if v4l2-ctl is installed
if ! command -v v4l2-ctl &> /dev/null; then
    echo "❌ v4l2-ctl not found. Installing..."
    sudo apt-get update && sudo apt-get install -y v4l-utils
fi

# Device to test
DEVICE="/dev/video0"

echo ""
echo "📹 Device Information:"
v4l2-ctl -d $DEVICE --info | grep -E "(Driver|Card|Bus)"

echo ""
echo "📋 Supported Formats:"
v4l2-ctl -d $DEVICE --list-formats-ext | grep -A 5 "YUYV\|NV12"

echo ""
echo "🔗 USB Information:"
lsusb -t | grep -B2 -A2 "Driver=uvcvideo" || echo "Could not find USB info"

echo ""
echo "🎯 Current Format:"
v4l2-ctl -d $DEVICE --get-fmt-video

echo ""
echo "⏱️ Testing Different Resolutions:"
echo "(Each test captures 100 frames)"

# Function to test a format
test_format() {
    local width=$1
    local height=$2
    local pixfmt=$3
    
    echo ""
    echo "Testing: ${width}x${height} $pixfmt"
    
    # Set format
    v4l2-ctl -d $DEVICE --set-fmt-video=width=$width,height=$height,pixelformat=$pixfmt 2>/dev/null
    
    # Capture frames and measure FPS
    echo -n "Actual FPS: "
    v4l2-ctl -d $DEVICE --stream-mmap --stream-count=100 2>&1 | grep -oP 'fps: \K[0-9.]+' | tail -1
}

echo ""
echo "1️⃣ Testing 640x480 YUYV (should work at 60fps):"
test_format 640 480 YUYV

echo ""
echo "2️⃣ Testing 1280x720 YUYV:"
test_format 1280 720 YUYV

echo ""
echo "3️⃣ Testing 1920x1080 YUYV (current problematic):"
test_format 1920 1080 YUYV

echo ""
echo "4️⃣ Testing 1920x1080 NV12 (different format):"
test_format 1920 1080 NV12

echo ""
echo "💡 RECOMMENDATIONS:"
echo "- If lower resolutions achieve 60fps: USB bandwidth limited"
echo "- If no resolution achieves 60fps: Device/driver limitation"
echo "- Try different USB ports (USB 3.0 preferred)"
echo "- Consider using 720p60 or NV12 format"
echo ""
echo "To manually set a format before running ndi-bridge:"
echo "  v4l2-ctl -d $DEVICE --set-fmt-video=width=1280,height=720,pixelformat=YUYV"
