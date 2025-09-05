#!/bin/bash
# Base system installation using debootstrap

install_base_system() {
    log "Installing base Ubuntu system (this will take 3-5 minutes)..."
    
    # Try to use a faster mirror or add wget options to prevent hanging
    # Export wget options to use timeouts and retries
    export DEBOOTSTRAP_WGET_OPTS="--timeout=10 --tries=3 --retry-connrefused"
    
    # Run debootstrap with minimal output
    # Include bash in the base system for chroot operations
    # Using German mirror which is much faster from this location
    debootstrap --arch=$UBUNTU_ARCH --variant=minbase --include=bash $UBUNTU_VERSION /mnt/usb \
        http://de.archive.ubuntu.com/ubuntu 2>&1 | \
        grep -E "^I: (Retrieving|Validating|Extracting|Installing)" || true
    
    log "Base system installed"
}

export -f install_base_system