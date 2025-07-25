#\!/bin/bash
# Build USB with logging

# Create log file with timestamp
LOG_FILE="build-logs/usb-build-$(date +%Y%m%d-%H%M%S).log"
mkdir -p build-logs
echo "Starting USB build at $(date)" | tee $LOG_FILE
echo "Log file: $LOG_FILE" | tee -a $LOG_FILE
echo "----------------------------------------" | tee -a $LOG_FILE

# Check if running as root
if [ "$(id -u)" != "0" ]; then 
    echo "ERROR: This script must be run as root (use sudo)" | tee -a $LOG_FILE
    exit 1
fi

# Get USB device
USB_DEVICE="${1:-/dev/sdb}"
echo "Target USB device: $USB_DEVICE" | tee -a $LOG_FILE

# Confirm device
echo "" | tee -a $LOG_FILE
echo "WARNING: This will ERASE ALL DATA on $USB_DEVICE" | tee -a $LOG_FILE
lsblk $USB_DEVICE 2>&1 | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE
read -p "Continue? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Build cancelled by user" | tee -a $LOG_FILE
    exit 1
fi

echo "" | tee -a $LOG_FILE
echo "Starting build..." | tee -a $LOG_FILE
echo "You can monitor progress with: tail -f $LOG_FILE" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

# Run the modular build script (final script is obsolete)
# Save all output to log file but only show errors and progress to console
./scripts/build-ndi-usb-modular.sh $USB_DEVICE > $LOG_FILE 2>&1 &
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
    echo "Log saved to: $LOG_FILE" | tee -a $LOG_FILE
else
    echo "" | tee -a $LOG_FILE
    echo "BUILD FAILED! Check log for errors: $LOG_FILE" | tee -a $LOG_FILE
    exit 1
fi
