#!/bin/bash
# NDI Bridge Quick Test Script for Ubuntu N100
# This script updates, compiles, sets capabilities, and runs the NDI bridge

set -e  # Exit on error

echo "🚀 NDI Bridge Quick Test Script v2.1.0"
echo "======================================"

# Set NDI SDK path if not already set
if [ -z "$NDI_SDK_DIR" ]; then
    export NDI_SDK_DIR="$HOME/ndi-test/NDI SDK for Linux"
    echo "✅ Set NDI_SDK_DIR to: $NDI_SDK_DIR"
fi

# Get to the repository root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo ""
echo "📥 Updating repository..."
git checkout fix/linux-v4l2-latency
git pull

echo ""
echo "🔨 Building v2.1.0..."
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

echo ""
echo "🔐 Setting capabilities..."
sudo setcap 'cap_sys_nice,cap_ipc_lock+ep' ./bin/ndi-bridge

echo ""
echo "✅ Build complete!"

# Show version by running with no args (shows usage which includes version)
echo ""
echo "📋 Version info:"
./bin/ndi-bridge --help 2>&1 | head -1 || true

echo ""
echo "🎥 Starting NDI Bridge..."
echo "Device: /dev/video0"
echo "NDI Name: NZXT HD60"
echo "Mode: EXTREME LOW LATENCY (v2.1.0)"
echo ""
echo "Features:"
echo "  - 2 buffers (absolute minimum)"
echo "  - Busy-wait (no poll overhead)"
echo "  - CPU affinity to core 3"
echo "  - RT priority 90"
echo "  - Memory locked"
echo ""
echo "Press Ctrl+C to stop"
echo "======================================"
echo ""

# Run with proper arguments (positional for v2.x)
./bin/ndi-bridge /dev/video0 "NZXT HD60"
