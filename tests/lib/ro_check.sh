#!/bin/bash
# Read-only filesystem verification for all tests
# MUST be sourced by all test modules to ensure test validity

# Function to verify filesystem is read-only
# This is CRITICAL for test validity - tests must run against RO filesystem
# to ensure they reflect real-world conditions
verify_readonly_filesystem() {
    local device_ip="${1:-$TEST_BOX_IP}"
    local ssh_user="${SSH_USER:-root}"
    local ssh_pass="${SSH_PASS:-newlevel}"
    
    if [ -z "$device_ip" ]; then
        echo "ERROR: No device IP provided for RO filesystem check"
        return 1
    fi
    
    # Check if filesystem is read-only
    local ro_status=$(sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no \
        "$ssh_user@$device_ip" "mount | grep ' / ' | grep -c 'ro,'" 2>/dev/null || echo "0")
    
    if [ "$ro_status" -eq 0 ] || [ "$ro_status" = "0" ]; then
        echo "================================================"
        echo "FATAL ERROR: Filesystem is NOT read-only!"
        echo "================================================"
        echo "Device: $device_ip"
        echo ""
        echo "Tests CANNOT proceed - the root filesystem must be read-only"
        echo "to ensure test validity and real-world conditions."
        echo ""
        echo "To fix this, run on the device:"
        echo "  ndi-bridge-ro"
        echo ""
        echo "Then re-run the tests."
        echo "================================================"
        return 1
    else
        echo "✓ Filesystem verified as READ-ONLY (required for test validity)"
        return 0
    fi
}

# Export the function so it's available to sourcing scripts
export -f verify_readonly_filesystem