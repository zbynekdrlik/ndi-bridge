#!/bin/bash
# Install helper scripts module

install_helper_scripts() {
    log "Installing helper scripts..."
    
    # Copy all helper scripts to the target system
    local HELPER_DIR="$(dirname "$0")/helper-scripts"
    
    if [ -d "$HELPER_DIR" ]; then
        cp -r "$HELPER_DIR"/* /mnt/usb/usr/local/bin/
        chmod +x /mnt/usb/usr/local/bin/ndi-bridge-*
    else
        warn "Helper scripts directory not found, creating inline..."
        # If helper scripts directory doesn't exist, create them inline
        # This is a fallback for backward compatibility
        create_inline_helper_scripts
    fi
}

create_inline_helper_scripts() {
    # This function creates helper scripts inline if the separate files don't exist
    # For backward compatibility with the original monolithic script
    
    # We'll include minimal versions here
    cat > /mnt/usb/usr/local/bin/ndi-bridge-help << 'EOF'
#!/bin/bash
echo "NDI Bridge Commands:"
echo "  ndi-bridge-info      - Display system status"
echo "  ndi-bridge-set-name  - Set device name"
echo "  ndi-bridge-logs      - View logs"
echo "  ndi-bridge-update    - Update binary"
echo "  ndi-bridge-netstat   - Network status"
echo "  ndi-bridge-netmon    - Network monitor"
EOF
    chmod +x /mnt/usb/usr/local/bin/ndi-bridge-help
}

export -f install_helper_scripts create_inline_helper_scripts