#!/bin/bash
# NDI-Bridge USB Linux Builder - Modular Version
# This is the main script that sources all modules

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all modules in order
source "$SCRIPT_DIR/build-modules/00-variables.sh"
source "$SCRIPT_DIR/build-modules/01-functions.sh"
source "$SCRIPT_DIR/build-modules/02-prerequisites.sh"
source "$SCRIPT_DIR/build-modules/03-partition.sh"
source "$SCRIPT_DIR/build-modules/04-mount.sh"
source "$SCRIPT_DIR/build-modules/05-debootstrap.sh"
source "$SCRIPT_DIR/build-modules/06-system-config.sh"
source "$SCRIPT_DIR/build-modules/07-base-setup.sh"
source "$SCRIPT_DIR/build-modules/08-network.sh"
source "$SCRIPT_DIR/build-modules/09-ndi-service.sh"
source "$SCRIPT_DIR/build-modules/10-tty-config.sh"
source "$SCRIPT_DIR/build-modules/11-filesystem.sh"
source "$SCRIPT_DIR/build-modules/12-helper-scripts.sh"
source "$SCRIPT_DIR/build-modules/13-helper-scripts-inline.sh"

# Copy NDI files
copy_ndi_files() {
    log "Copying NDI files..."
    
    # Create directories first
    mkdir -p /mnt/usb/opt/ndi-bridge
    
    # Copy NDI binary
    cp "$NDI_BINARY_PATH" /mnt/usb/opt/ndi-bridge/
    chmod +x /mnt/usb/opt/ndi-bridge/ndi-bridge
    
    # Copy NDI libraries
    mkdir -p /mnt/usb/usr/local/lib
    cp "$NDI_SDK_PATH/lib/x86_64-linux-gnu/libndi.so.6.2.0" /mnt/usb/usr/local/lib/
    cd /mnt/usb/usr/local/lib
    ln -s libndi.so.6.2.0 libndi.so.6
    ln -s libndi.so.6 libndi.so
    cd - > /dev/null
}

# Assemble the full configuration script
assemble_configuration() {
    log "Assembling configuration script..."
    
    # Start the configuration script
    configure_system
    setup_base_system
    configure_network
    configure_ndi_service
    configure_ttys
    configure_filesystem
    create_all_helper_scripts
    
    # Replace the version placeholder
    sed -i "s/BUILD_SCRIPT_VERSION_PLACEHOLDER/$BUILD_SCRIPT_VERSION/" /mnt/usb/tmp/configure-system.sh
}

# Run setup in chroot
run_chroot_setup() {
    log "Running setup in chroot (this will take 5-10 minutes)..."
    
    # Mount necessary filesystems
    mount --bind /dev /mnt/usb/dev
    mount --bind /dev/pts /mnt/usb/dev/pts
    mount --bind /proc /mnt/usb/proc
    mount --bind /sys /mnt/usb/sys
    
    # Set up environment to reduce warnings
    export DEBIAN_FRONTEND=noninteractive
    export USB_DEVICE  # Pass USB device to chroot
    
    # Run setup script
    chroot /mnt/usb /tmp/configure-system.sh 2>&1 | \
        while IFS= read -r line; do
            # Filter out verbose package installation output and known warnings
            if [[ ! "$line" =~ ^(Get:|Fetched|Reading|Building|Selecting|Preparing|Unpacking|Setting) ]] && \
               [[ ! "$line" =~ "dpkg-preconfigure: unable to re-open stdin" ]] && \
               [[ ! "$line" =~ "E: Can not write log" ]]; then
                echo "$line"
            fi
        done
    
    # Unmount
    umount /mnt/usb/dev/pts
    umount /mnt/usb/dev
    umount /mnt/usb/proc
    umount /mnt/usb/sys
}

# Cleanup
cleanup() {
    log "Cleaning up..."
    rm -f /mnt/usb/tmp/configure-system.sh
    sync
}

# Main execution
main() {
    log "Starting NDI-Bridge USB Linux Builder (Modular Version $BUILD_SCRIPT_VERSION)"
    log "Target device: $USB_DEVICE"
    
    check_prerequisites
    
    # Warning about data erasure
    warn "This will ERASE ALL DATA on $USB_DEVICE"
    log "Proceeding with USB creation..."
    
    partition_usb
    mount_filesystems
    install_base_system
    assemble_configuration
    copy_ndi_files
    install_helper_scripts
    run_chroot_setup
    cleanup
    unmount_all
    
    log "Build complete! You can now boot from the USB drive."
    log "Default credentials: root / $ROOT_PASSWORD"
    log ""
    log "The system will:"
    log "  - Boot automatically (0s GRUB timeout)"
    log "  - Get IP via DHCP"
    log "  - Start NDI-Bridge automatically"
    log "  - Show live logs on TTY1"
    log "  - Show system menu on TTY2"
    log ""
    log "SSH access: ssh root@<IP>"
    log "Run 'ndi-bridge-help' for available commands"
}

# Run main function
main "$@"