#!/bin/bash
# Common functions used throughout the build process

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

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        error "This script must be run as root"
    fi
}

# Validate USB device
validate_usb_device() {
    if [ ! -b "$USB_DEVICE" ]; then
        error "USB device $USB_DEVICE not found"
    fi
    
    # Check if device is mounted
    if mount | grep -q "^$USB_DEVICE"; then
        error "$USB_DEVICE is mounted. Please unmount it first."
    fi
}

# Export functions
export -f log error warn command_exists check_root validate_usb_device