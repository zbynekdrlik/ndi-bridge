#!/bin/bash
# Build NDI Bridge USB image for WSL/Windows (works with Rufus)

set -e

# Create log file with timestamp
LOG_FILE="build-logs/image-build-$(date +%Y%m%d-%H%M%S).log"
mkdir -p build-logs

# Auto-redirect all output to log file if running in terminal
# This prevents terminal crashes from verbose output
if [ -t 1 ]; then
    # Only show essential info before redirect
    echo "Build starting - log: $LOG_FILE"
    echo "Monitor with: tail -f $LOG_FILE"
    # Redirect everything to log file immediately
    exec > "$LOG_FILE" 2>&1
fi

# Now safe to output verbose info (goes to log or console)
echo "Starting image build at $(date)"
echo "Log file: $LOG_FILE"
echo "----------------------------------------"

# Check if running as root
if [ "$(id -u)" != "0" ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check for required binaries - build them if missing
echo "Checking for required binaries..."
if [ ! -f "build/bin/ndi-capture" ] || [ ! -f "build/bin/ndi-display" ]; then
    echo "Required binaries missing. Setting up build environment..."
    
    # Check if NDI SDK is installed, if not run setup
    if [ ! -d "NDI SDK for Linux" ]; then
        echo "NDI SDK not found. Running setup script..."
        if [ -f "setup-build-environment.sh" ]; then
            ./setup-build-environment.sh
            if [ $? -ne 0 ]; then
                echo "ERROR: Setup script failed"
                exit 1
            fi
        else
            echo "ERROR: setup-build-environment.sh not found"
            exit 1
        fi
    fi
    
    # Build the binaries using build.sh
    echo "Building NDI binaries..."
    if [ -f "build.sh" ]; then
        ./build.sh
        if [ $? -ne 0 ]; then
            echo "ERROR: Build script failed"
            exit 1
        fi
    else
        echo "ERROR: build.sh not found"
        exit 1
    fi
    
    # Verify binaries exist after build
    if [ ! -f "build/bin/ndi-capture" ] || [ ! -f "build/bin/ndi-display" ]; then
        echo "ERROR: Failed to build required binaries"
        exit 1
    fi
fi
echo "✓ ndi-capture binary found"
echo "✓ ndi-display binary found"

# Clean up any stuck resources from previous builds
echo "Cleaning up stuck resources from previous builds..."
# Kill stuck build processes
pkill -f "build-ndi-usb-modular" 2>/dev/null || true
# Unmount any leftover mounts
umount /mnt/usb/* 2>/dev/null || true
umount /mnt/usb 2>/dev/null || true
# Clean up stale loop devices
for loop in $(losetup -a | grep "ndi-bridge.img" | cut -d: -f1); do
    kpartx -d "$loop" 2>/dev/null || true
    losetup -d "$loop" 2>/dev/null || true
done

# Create image file (8GB for Chrome and dependencies)
IMAGE_FILE="${1:-ndi-bridge.img}"
IMAGE_SIZE="8G"

echo "Creating disk image: $IMAGE_FILE ($IMAGE_SIZE)"

# Create sparse file
echo "Creating $IMAGE_SIZE disk image..."
dd if=/dev/zero of="$IMAGE_FILE" bs=1 count=0 seek=$IMAGE_SIZE 2>&1

# Create loop device
echo "Setting up loop device..."
LOOP_DEVICE=$(losetup --find --show "$IMAGE_FILE")
echo "Loop device: $LOOP_DEVICE"

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    
    # First unmount all the special filesystems that might be mounted
    umount /mnt/usb/dev/pts 2>/dev/null || true
    umount /mnt/usb/proc 2>/dev/null || true
    umount /mnt/usb/sys 2>/dev/null || true
    umount /mnt/usb/dev 2>/dev/null || true
    umount /mnt/usb/boot/efi 2>/dev/null || true
    umount /mnt/usb/boot 2>/dev/null || true
    umount /mnt/usb 2>/dev/null || true
    
    # Remove device mapper entries
    dmsetup remove /dev/mapper/loop*p* 2>/dev/null || true
    
    # Clean up kpartx mappings for all loops
    for loop in $(losetup -a | grep "$IMAGE_FILE" | cut -d: -f1); do
        kpartx -d "$loop" 2>/dev/null || true
    done
    
    # Now detach loop devices
    if [ -n "$LOOP_DEVICE" ]; then
        losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    fi
    
    # Clean up any remaining loop devices associated with our image file
    if [ -f "$IMAGE_FILE" ]; then
        for loop in $(losetup -a | grep "$IMAGE_FILE" | cut -d: -f1); do
            echo "Detaching loop device: $loop"
            losetup -d "$loop" 2>/dev/null || true
        done
    fi
}
trap cleanup EXIT

echo ""
echo "Starting build..."
echo ""

# Run the modular build script with loop device
# All output goes to log file only
./scripts/build-ndi-usb-modular.sh $LOOP_DEVICE 2>&1
BUILD_STATUS=$?

# Check exit status
if [ $BUILD_STATUS -eq 0 ]; then
    echo ""
    echo "BUILD SUCCESSFUL!"
    echo "Image created: $IMAGE_FILE"
    echo "You can now write this image to USB using:"
    echo "  - Rufus on Windows"
    echo "  - dd on Linux: dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress"
    echo "Log saved to: $LOG_FILE"
    
    # Show image info
    echo ""
    echo "Image information:"
    ls -lh "$IMAGE_FILE"
else
    echo ""
    echo "BUILD FAILED! Check log for errors: $LOG_FILE"
    rm -f "$IMAGE_FILE"  # Clean up failed image
    exit 1
fi