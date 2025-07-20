#!/bin/bash
# Base system installation using debootstrap

install_base_system() {
    log "Installing base Ubuntu system (this will take 3-5 minutes)..."
    
    # Run debootstrap with minimal output
    debootstrap --arch=$UBUNTU_ARCH --variant=minbase $UBUNTU_VERSION /mnt/usb \
        http://archive.ubuntu.com/ubuntu 2>&1 | \
        grep -E "^I: (Retrieving|Validating|Extracting|Installing)" || true
    
    log "Base system installed"
}

export -f install_base_system