#!/bin/bash
# Check prerequisites for the build process

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    check_root
    
    # Check USB device
    validate_usb_device
    
    # Check if NDI binary exists
    if [ ! -f "$NDI_BINARY_PATH" ]; then
        error "NDI binary not found at $NDI_BINARY_PATH"
    fi
    
    # Check if NDI SDK exists
    if [ ! -d "$NDI_SDK_PATH" ]; then
        error "NDI SDK not found at $NDI_SDK_PATH"
    fi
    
    # Check for required tools
    local required_tools=("debootstrap" "parted" "mkfs.fat" "mkfs.btrfs" "grub-install")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            error "Required tool '$tool' is not installed"
        fi
    done
    
    # Install debootstrap if missing
    if ! command_exists debootstrap; then
        log "Installing debootstrap..."
        apt-get update && apt-get install -y debootstrap
    fi
    
    log "All prerequisites satisfied"
}

export -f check_prerequisites