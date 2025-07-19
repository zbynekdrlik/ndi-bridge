#!/bin/bash
# NDI-Bridge USB Linux Builder - SAFE TEST VERSION
# This version limits output to prevent Claude/terminal crashes
# Creates a complete bootable USB Linux system with NDI-Bridge

set -e

# Configuration
USB_DEVICE="${1:-/dev/sdb}"
NDI_BINARY_PATH="$(dirname "$0")/../build/bin/ndi-bridge"
NDI_SDK_PATH="$(dirname "$0")/../../NDI SDK for Linux"
OUTPUT_LIMIT=100  # Limit progress indicators

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        error "This script must be run as root"
    fi
    
    # Check USB device
    if [ ! -b "$USB_DEVICE" ]; then
        error "USB device $USB_DEVICE not found"
    fi
    
    # Check NDI binary
    if [ ! -f "$NDI_BINARY_PATH" ]; then
        error "NDI-bridge binary not found at $NDI_BINARY_PATH"
    fi
    
    # Check NDI SDK
    if [ ! -d "$NDI_SDK_PATH" ]; then
        error "NDI SDK not found at $NDI_SDK_PATH"
    fi
    
    # Check required tools
    for tool in debootstrap parted mkfs.ext4 mkfs.vfat; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is required but not installed"
        fi
    done
}

# Safe output wrapper - limits lines and adds counter
safe_output() {
    local count=0
    local max_dots=$OUTPUT_LIMIT
    
    while IFS= read -r line; do
        count=$((count + 1))
        if [ $count -le $max_dots ]; then
            echo -n "."
        elif [ $count -eq $((max_dots + 1)) ]; then
            echo -n " [output limited]"
        fi
        # Still process all input, just don't display it
    done
    echo " Done! (processed $count lines)"
}

# Install base system with safe output
install_base_system() {
    log "Installing Ubuntu 24.04 base system (this will take 5-10 minutes)..."
    log "Progress (limited to $OUTPUT_LIMIT dots): "
    
    # Run debootstrap with output limiting
    debootstrap --arch=amd64 noble /mnt/usb http://archive.ubuntu.com/ubuntu/ 2>&1 | safe_output
}

# Run setup in chroot with safe output
run_chroot_setup() {
    log "Running setup in chroot (this will take 5-10 minutes)..."
    
    # Mount necessary filesystems
    mount --bind /dev /mnt/usb/dev
    mount --bind /dev/pts /mnt/usb/dev/pts
    mount --bind /proc /mnt/usb/proc
    mount --bind /sys /mnt/usb/sys
    
    # Set up environment to reduce warnings
    export DEBIAN_FRONTEND=noninteractive
    
    # Run setup script with limited output
    log "Installing packages (output limited)..."
    chroot /mnt/usb /tmp/setup.sh 2>&1 | safe_output
    
    # Unmount
    umount /mnt/usb/dev/pts
    umount /mnt/usb/dev
    umount /mnt/usb/proc
    umount /mnt/usb/sys
}

# Test mode - just check prerequisites and show what would be done
test_mode() {
    log "Running in TEST MODE - no changes will be made"
    
    check_prerequisites
    
    log "Test results:"
    log "  USB Device: $USB_DEVICE (found)"
    log "  NDI Binary: $NDI_BINARY_PATH (found)"
    log "  NDI SDK: $NDI_SDK_PATH (found)"
    log "  All required tools are installed"
    
    log ""
    log "The full build would:"
    log "  1. Partition $USB_DEVICE with GPT (512MB EFI + remaining for root)"
    log "  2. Format partitions (FAT32 for EFI, ext4 for root)"
    log "  3. Install Ubuntu 24.04 base system"
    log "  4. Configure system with NDI-Bridge"
    log "  5. Set up read-only root filesystem"
    log "  6. Configure network bridging"
    log "  7. Install GRUB bootloader"
    
    log ""
    log "To run the actual build, use: $0 $USB_DEVICE --build"
}

# Main execution
main() {
    log "NDI-Bridge USB Linux Builder - SAFE TEST VERSION"
    log "Target device: $USB_DEVICE"
    
    if [ "${2}" != "--build" ]; then
        test_mode
        exit 0
    fi
    
    check_prerequisites
    
    # Confirm with user
    warn "This will ERASE ALL DATA on $USB_DEVICE"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        error "Aborted by user"
    fi
    
    log "Starting build with output limiting enabled..."
    log "Full build functionality will be added after testing output limits"
    
    # For now, just test the output limiting with a simple command
    log "Testing output limiter with package list:"
    apt list --installed 2>&1 | safe_output
}

# Run main function
main "$@"