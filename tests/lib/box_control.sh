#!/bin/bash
# Box control functions for testing

# Reboot the box
box_reboot() {
    log_info "Rebooting box at $TEST_BOX_IP..."
    box_ssh "reboot" || true
    sleep 5  # Give time for reboot to start
}

# Wait for box to complete boot
box_wait_for_boot() {
    local timeout="${1:-$TEST_TIMEOUT_BOOT}"
    
    # First wait for box to come online
    if ! box_wait_online "$timeout"; then
        return 1
    fi
    
    # Then wait for services to start
    log_info "Waiting for services to start..."
    local count=0
    while true; do
        local capture_status=$(box_service_status "ndi-capture")
        if [ "$capture_status" = "active" ]; then
            log_info "Services are ready"
            # PTP takes additional time to synchronize after reboot
            # Capture needs time to stabilize CPU usage after boot
            log_info "Waiting additional 30s for PTP synchronization and capture stabilization..."
            sleep 30
            return 0
        fi
        
        sleep 2
        count=$((count + 2))
        if [ $count -ge "$TEST_TIMEOUT_SERVICE" ]; then
            log_error "Timeout waiting for services to start"
            return 1
        fi
        echo -n "."
    done
}

# Deploy image to box (fast deployment)
box_deploy_image() {
    local image_file="${1:-$BUILD_IMAGE_PATH}"
    
    if [ ! -f "$image_file" ]; then
        log_error "Image file $image_file not found"
        return 1
    fi
    
    log_info "Deploying image to box..."
    
    # Mount image locally
    local mount_dir=$(mktemp -d)
    trap "sudo umount $mount_dir 2>/dev/null; rm -rf $mount_dir" RETURN
    
    sudo mount -o loop,offset=537919488,ro "$image_file" "$mount_dir"
    
    # Remount filesystem as read-write
    log_info "Remounting filesystem as read-write..."
    box_ssh "mount -o remount,rw /"
    
    # Stop services
    log_info "Stopping services on box..."
    box_ssh "systemctl stop ndi-capture ndi-display@* ndi-bridge-collector 2>/dev/null || true"
    sleep 2
    
    # Deploy binaries
    log_info "Deploying binaries..."
    for binary in ndi-capture ndi-display; do
        if [ -f "$mount_dir/opt/ndi-bridge/$binary" ]; then
            sshpass -p "$TEST_BOX_PASS" scp $TEST_BOX_SSH_OPTS \
                "$mount_dir/opt/ndi-bridge/$binary" \
                "${TEST_BOX_USER}@${TEST_BOX_IP}:/opt/ndi-bridge/" || true
        fi
    done
    
    # Deploy scripts
    log_info "Deploying scripts..."
    for script in $mount_dir/usr/local/bin/ndi-bridge-*; do
        if [ -f "$script" ]; then
            local script_name=$(basename "$script")
            sshpass -p "$TEST_BOX_PASS" scp $TEST_BOX_SSH_OPTS \
                "$script" "${TEST_BOX_USER}@${TEST_BOX_IP}:/usr/local/bin/" || true
        fi
    done
    
    # Deploy configuration files
    log_info "Deploying configuration files..."
    if [ -f "$mount_dir/etc/ndi-bridge/config" ]; then
        box_ssh "mkdir -p /etc/ndi-bridge"
        sshpass -p "$TEST_BOX_PASS" scp $TEST_BOX_SSH_OPTS \
            "$mount_dir/etc/ndi-bridge/config" \
            "${TEST_BOX_USER}@${TEST_BOX_IP}:/etc/ndi-bridge/config" || true
    fi
    
    # Deploy run.sh script
    if [ -f "$mount_dir/opt/ndi-bridge/run.sh" ]; then
        sshpass -p "$TEST_BOX_PASS" scp $TEST_BOX_SSH_OPTS \
            "$mount_dir/opt/ndi-bridge/run.sh" \
            "${TEST_BOX_USER}@${TEST_BOX_IP}:/opt/ndi-bridge/run.sh" || true
        box_ssh "chmod +x /opt/ndi-bridge/run.sh"
    fi
    
    # Deploy systemd service files
    log_info "Deploying systemd service files..."
    for service in ndi-display@.service ndi-capture.service ndi-display-monitor.service; do
        if [ -f "$mount_dir/etc/systemd/system/$service" ]; then
            sshpass -p "$TEST_BOX_PASS" scp $TEST_BOX_SSH_OPTS \
                "$mount_dir/etc/systemd/system/$service" \
                "${TEST_BOX_USER}@${TEST_BOX_IP}:/etc/systemd/system/$service" || true
        fi
    done
    box_ssh "systemctl daemon-reload"
    
    # Restart services
    log_info "Starting services..."
    box_ssh "systemctl start ndi-capture 2>/dev/null || true"
    box_ssh "systemctl start ndi-display@1 2>/dev/null || true"
    
    # Remount filesystem as read-only
    log_info "Remounting filesystem as read-only..."
    box_ssh "mount -o remount,ro /"
    
    sleep 3
    return 0
}

# Start a service on the box
box_start_service() {
    local service="$1"
    log_info "Starting service: $service"
    box_ssh "systemctl start $service"
}

# Stop a service on the box
box_stop_service() {
    local service="$1"
    log_info "Stopping service: $service"
    box_ssh "systemctl stop $service"
}

# Restart a service on the box
box_restart_service() {
    local service="$1"
    log_info "Restarting service: $service"
    box_ssh "systemctl restart $service"
}

# Check if capture device is present
box_check_capture_device() {
    local device="${1:-$TEST_CAPTURE_DEVICE}"
    local result=$(box_ssh "[ -e '$device' ] && echo 'present' || echo 'missing'")
    [ "$result" = "present" ]
}

# Assign NDI stream to display
box_assign_display() {
    local stream_name="$1"
    local display_id="${2:-$TEST_DISPLAY_ID}"
    
    log_info "Assigning '$stream_name' to display $display_id"
    
    # Stop existing display service if running
    box_ssh "systemctl stop ndi-display@${display_id} 2>/dev/null || true"
    sleep 1
    
    # Create config file directly (non-interactive)
    # This mimics what ndi-display-config does but without prompts
    box_ssh "ndi-bridge-rw"
    box_ssh "mkdir -p /etc/ndi-bridge"
    box_ssh "echo 'STREAM_NAME=\"$stream_name\"' > /etc/ndi-bridge/display-${display_id}.conf"
    box_ssh "ndi-bridge-ro"
    
    # Start the display service
    box_ssh "systemctl start ndi-display@${display_id}"
    sleep 3
    
    # Verify it started
    local status=$(box_service_status "ndi-display@${display_id}")
    [ "$status" = "active" ]
}

# Remove NDI stream from display
box_remove_display() {
    local display_id="${1:-$TEST_DISPLAY_ID}"
    
    log_info "Removing stream from display $display_id"
    
    # Stop the service (works on read-only filesystem)
    box_ssh "systemctl stop ndi-display@${display_id} 2>/dev/null || true"
    
    # Use box's proper commands to handle filesystem and remove config
    # Config is at /etc/ndi-bridge/ not /etc/ndi-display/
    box_ssh "ndi-bridge-rw && rm -f /etc/ndi-bridge/display-${display_id}.conf && ndi-bridge-ro"
}

# Get list of available NDI streams  
box_list_ndi_streams() {
    # The box itself broadcasts as "NDI-BRIDGE (USB Capture)" when capture is active
    # NDI prepends the hostname in capitals to the configured name
    # Check if the capture service is running and outputting NDI
    local capture_status=$(box_ssh "systemctl is-active ndi-capture 2>/dev/null")
    if [ "$capture_status" = "active" ]; then
        echo "NDI-BRIDGE (USB Capture)"
    fi
    
    # Also check for any configured display streams
    local displays=$(box_ssh "ls /etc/ndi-bridge/display-*.conf 2>/dev/null")
    if [ -n "$displays" ]; then
        for conf in $displays; do
            local stream=$(box_ssh "grep STREAM_NAME $conf 2>/dev/null | cut -d'\"' -f2")
            [ -n "$stream" ] && echo "$stream"
        done
    fi
}

# Get system information
box_get_system_info() {
    echo "=== System Information ==="
    echo "Hostname: $(box_ssh 'hostname')"
    echo "IP: $(box_ssh "ip -4 addr show br0 2>/dev/null | grep inet | awk '{print \$2}' | cut -d/ -f1")"
    echo "Uptime: $(box_ssh 'uptime -p')"
    echo "Version: $(box_ssh '/opt/ndi-bridge/ndi-capture --version 2>/dev/null || echo unknown')"
    echo "Build: $(box_ssh 'cat /etc/ndi-bridge/build-script-version 2>/dev/null || echo unknown')"
}

# Check PTP synchronization
box_check_ptp_sync() {
    local ptp_status=$(box_ssh "systemctl is-active ptp4l" | tr -d '\n')
    local phc2sys_status=$(box_ssh "systemctl is-active phc2sys" | tr -d '\n')
    
    if [ "$ptp_status" = "active" ] && [ "$phc2sys_status" = "active" ]; then
        # Check if actually synchronized
        local ptp_sync=$(box_ssh "journalctl -u ptp4l -n 10 --no-pager | grep -c 'master offset' || echo 0")
        if [ "$ptp_sync" -gt 0 ]; then
            echo "PTP_SYNCHRONIZED"
        else
            echo "PTP_ACTIVE_NOT_SYNCED"
        fi
    else
        echo "PTP_INACTIVE"
    fi
}

# Check NTP synchronization
box_check_ntp_sync() {
    local ntp_status=$(box_ssh "timedatectl status | grep 'System clock synchronized' | awk '{print \$4}'" | tr -d '\n')
    if [ "$ntp_status" = "yes" ]; then
        echo "NTP_SYNCHRONIZED"
    else
        echo "NTP_NOT_SYNCHRONIZED"
    fi
}

# Get time sync status
box_get_time_sync_status() {
    local ptp_state=$(box_check_ptp_sync)
    local ntp_state=$(box_check_ntp_sync)
    
    echo "PTP: $ptp_state"
    echo "NTP: $ntp_state"
    
    if [ "$ptp_state" = "PTP_SYNCHRONIZED" ]; then
        echo "TIME_SYNC: PTP (Primary)"
    elif [ "$ntp_state" = "NTP_SYNCHRONIZED" ]; then
        echo "TIME_SYNC: NTP (Fallback)"
    else
        echo "TIME_SYNC: NONE"
    fi
}

# Get service logs
box_get_logs() {
    local service="$1"
    local lines="${2:-50}"
    box_ssh "journalctl -u $service -n $lines --no-pager"
}

# Check network connectivity
box_check_network() {
    local ip=$(box_ssh "ip -4 addr show br0 2>/dev/null | grep inet | awk '{print \$2}' | cut -d/ -f1")
    if [ -n "$ip" ]; then
        log_info "Box has IP: $ip"
        return 0
    else
        log_error "Box has no IP address"
        return 1
    fi
}

# Check web interface
box_check_web_interface() {
    local response=$(curl -s -o /dev/null -w "%{http_code}" -m 5 \
        --user admin:newlevel "http://${TEST_BOX_IP}/" 2>/dev/null)
    
    if [ "$response" = "200" ]; then
        log_info "Web interface is accessible"
        return 0
    else
        log_error "Web interface not accessible (HTTP $response)"
        return 1
    fi
}

# Global cleanup function to restore box to clean state
box_cleanup_all() {
    log_info "Cleaning up test environment..."
    
    # Stop all display services
    for i in 1 2 3; do
        box_ssh "systemctl stop ndi-display@$i 2>/dev/null || true"
    done
    
    # Remove all display configs using box commands
    box_ssh "ndi-bridge-rw"
    box_ssh "rm -f /etc/ndi-bridge/display-*.conf 2>/dev/null || true"
    box_ssh "ndi-bridge-ro"
    
    # Ensure capture service is running
    if ! box_service_status "ndi-capture" | grep -q "active"; then
        box_ssh "systemctl restart ndi-capture"
    fi
    
    log_info "Cleanup complete"
}

# Monitor capture for stability
box_monitor_capture() {
    local duration="${1:-10}"
    local samples=()
    
    log_info "Monitoring capture for ${duration} seconds..." >&2
    
    for ((i=0; i<duration; i++)); do
        local status=$(box_get_capture_status)
        local fps=$(parse_status_value "$status" "CURRENT_FPS")
        samples+=("$fps")
        sleep 1
        echo -n "." >&2
    done
    echo "" >&2
    
    # Calculate average
    local sum=0
    local count=0
    for fps in "${samples[@]}"; do
        if [ -n "$fps" ]; then
            # Remove decimal part for calculation
            fps_int=$(echo "$fps" | cut -d'.' -f1)
            sum=$((sum + fps_int))
            count=$((count + 1))
        fi
    done
    
    if [ $count -gt 0 ]; then
        local avg=$((sum / count))
        log_info "Average FPS over ${duration}s: $avg" >&2
        echo "$avg"
    else
        log_error "No FPS data collected" >&2
        echo "0"
    fi
}