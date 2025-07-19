#!/bin/bash
# Run NDI Bridge at 720p60 for better latency
# This is a workaround for devices that can't handle 1080p60

set -e

echo "🎯 NDI Bridge 720p60 Mode"
echo "========================"
echo ""
echo "This runs at 720p60 for lower latency when 1080p60 fails"
echo ""

# Set NDI SDK path if not already set
if [ -z "$NDI_SDK_DIR" ]; then
    export NDI_SDK_DIR="$HOME/ndi-test/NDI SDK for Linux"
fi

# Get to the repository root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Ensure built
if [ ! -f "build/bin/ndi-bridge" ]; then
    echo "⚠️ Building first..."
    mkdir -p build
    cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j$(nproc)
    cd ..
fi

# Set capabilities
sudo setcap 'cap_sys_nice,cap_ipc_lock+ep' ./build/bin/ndi-bridge

# Force 720p60 mode
echo "🎥 Setting capture to 720p60 YUYV..."
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1280,height=720,pixelformat=YUYV

# Verify the setting
echo ""
echo "📋 Current format:"
v4l2-ctl -d /dev/video0 --get-fmt-video | grep -E "(Width|Height|Pixel Format)"

echo ""
echo "🚀 Starting NDI Bridge at 720p60..."
echo "Expected: 60 FPS, lower latency"
echo ""
echo "Press Ctrl+C to stop"
echo "========================"
echo ""

# Run ndi-bridge
./build/bin/ndi-bridge /dev/video0 "NZXT HD60 720p"
