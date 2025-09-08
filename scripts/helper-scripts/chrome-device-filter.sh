#!/bin/bash
# Chrome Device Filter - Hides hardware devices from Chrome
# This script uses pw-cli to deny Chrome access to hardware devices

set -e

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/999}"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
    logger -t chrome-filter "$*"
}

# Find Chrome's client ID in PipeWire
get_chrome_client_id() {
    pw-cli ls Client 2>/dev/null | \
        grep -B5 -E 'application.name.*Chrome|application.process.binary.*chrome' | \
        grep "id:" | awk '{print $2}' | head -1
}

# Hide devices from Chrome
filter_chrome_devices() {
    local chrome_id=$(get_chrome_client_id)
    
    if [ -z "$chrome_id" ]; then
        return  # Chrome not running
    fi
    
    log "Chrome client ID: $chrome_id"
    
    # Get all hardware device nodes
    local hw_nodes=$(pw-cli ls Node 2>/dev/null | \
        grep -E 'usb_audio|CSCTEK|hdmi|HDMI|alsa_' | \
        grep "id:" | awk '{print $2}')
    
    # Deny Chrome access to each hardware node
    for node_id in $hw_nodes; do
        # Set permission to deny (0 = no access)
        pw-cli set-param "$chrome_id" Permissions \
            "[ { id: $node_id, permissions: 0 } ]" 2>/dev/null || true
        log "Denied Chrome access to node $node_id"
    done
    
    # Grant Chrome access to virtual devices
    local virtual_nodes=$(pw-cli ls Node 2>/dev/null | \
        grep -E 'intercom-speaker|intercom-microphone' | \
        grep "id:" | awk '{print $2}')
    
    for node_id in $virtual_nodes; do
        # Set permission to full access (7 = rwx)
        pw-cli set-param "$chrome_id" Permissions \
            "[ { id: $node_id, permissions: 7 } ]" 2>/dev/null || true
        log "Granted Chrome access to virtual node $node_id"
    done
}

# Main loop
main() {
    log "Chrome Device Filter starting..."
    
    # Wait for PipeWire
    while ! pw-cli info Core >/dev/null 2>&1; do
        log "Waiting for PipeWire..."
        sleep 2
    done
    
    log "Starting filter loop..."
    
    while true; do
        filter_chrome_devices
        sleep 3
    done
}

trap 'log "Chrome filter shutting down..."; exit 0' TERM INT

main "$@"