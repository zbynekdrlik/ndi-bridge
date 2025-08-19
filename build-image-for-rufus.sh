#!/bin/bash
# Build NDI Bridge USB image for WSL/Windows (works with Rufus)

set -e

# Create log file with timestamp
LOG_FILE="build-logs/image-build-$(date +%Y%m%d-%H%M%S).log"
mkdir -p build-logs
echo "Starting image build at $(date)" | tee $LOG_FILE
echo "Log file: $LOG_FILE" | tee -a $LOG_FILE
echo "----------------------------------------" | tee -a $LOG_FILE

# Check if running as root
if [ "$(id -u)" != "0" ]; then 
    echo "ERROR: This script must be run as root (use sudo)" | tee -a $LOG_FILE
    exit 1
fi

# Create image file (4GB should be enough)
IMAGE_FILE="${1:-ndi-bridge.img}"
IMAGE_SIZE="4G"

echo "Creating disk image: $IMAGE_FILE ($IMAGE_SIZE)" | tee -a $LOG_FILE

# Create sparse file
echo "Creating $IMAGE_SIZE disk image..." | tee -a $LOG_FILE
dd if=/dev/zero of="$IMAGE_FILE" bs=1 count=0 seek=$IMAGE_SIZE >> $LOG_FILE 2>&1

# Create loop device
echo "Setting up loop device..." | tee -a $LOG_FILE
LOOP_DEVICE=$(losetup --find --show "$IMAGE_FILE")
echo "Loop device: $LOOP_DEVICE" | tee -a $LOG_FILE

# Cleanup function
cleanup() {
    echo "Cleaning up..." | tee -a $LOG_FILE
    if [ -n "$LOOP_DEVICE" ]; then
        # Try to unmount and remove kpartx mappings first
        umount /mnt/usb/boot/efi 2>/dev/null || true
        umount /mnt/usb 2>/dev/null || true
        kpartx -d "$LOOP_DEVICE" 2>/dev/null || true
        losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    fi
    
    # Clean up any remaining loop devices associated with our image file
    if [ -f "$IMAGE_FILE" ]; then
        for loop in $(losetup -a | grep "$IMAGE_FILE" | cut -d: -f1); do
            echo "Detaching additional loop device: $loop" | tee -a $LOG_FILE
            losetup -d "$loop" 2>/dev/null || true
        done
    fi
}
trap cleanup EXIT

echo "" | tee -a $LOG_FILE
echo "Starting build..." | tee -a $LOG_FILE
echo "You can monitor progress with: tail -f $LOG_FILE" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

# Run the modular build script with loop device
# Save all output to log file but only show errors and progress to console
./scripts/build-ndi-usb-modular.sh $LOOP_DEVICE >> $LOG_FILE 2>&1 &
BUILD_PID=$!

# Monitor the build and show only important messages
echo "Build in progress. Showing only errors and key messages..."
tail -f $LOG_FILE | grep -E "(ERROR|FAIL|WARNING|SUCCESS|COMPLETE|Starting|Finished|Creating|Building|Installing|^\[|Step [0-9]|===)" &
TAIL_PID=$!

# Wait for build to complete
wait $BUILD_PID
BUILD_STATUS=$?

# Stop the tail process
kill $TAIL_PID 2>/dev/null

# Check exit status
if [ $BUILD_STATUS -eq 0 ]; then
    echo "" | tee -a $LOG_FILE
    echo "BUILD SUCCESSFUL!" | tee -a $LOG_FILE
    echo "Image created: $IMAGE_FILE" | tee -a $LOG_FILE
    echo "You can now write this image to USB using:" | tee -a $LOG_FILE
    echo "  - Rufus on Windows" | tee -a $LOG_FILE
    echo "  - dd on Linux: dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress" | tee -a $LOG_FILE
    echo "Log saved to: $LOG_FILE" | tee -a $LOG_FILE
    
    # Show image info
    echo "" | tee -a $LOG_FILE
    echo "Image information:" | tee -a $LOG_FILE
    ls -lh "$IMAGE_FILE" | tee -a $LOG_FILE
else
    echo "" | tee -a $LOG_FILE
    echo "BUILD FAILED! Check log for errors: $LOG_FILE" | tee -a $LOG_FILE
    rm -f "$IMAGE_FILE"  # Clean up failed image
    exit 1
fi