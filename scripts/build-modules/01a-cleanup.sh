#!/bin/bash
# Build cleanup module - runs before any build operations
# Ensures clean state by removing stuck mounts, loop devices, and processes
# from previous incomplete or failed builds

# Function to perform pre-build cleanup
perform_build_cleanup() {
    log "Performing pre-build cleanup..."
    
    local cleanup_performed=false
    
    # Kill any stuck build-related processes (excluding current build)
    cleanup_stuck_processes() {
        log "  Checking for stuck build processes..."
        local current_pid=$$
        local parent_pid=$PPID
        
        # Find processes related to build scripts
        local stuck_pids=$(ps aux | grep -E "(build-ndi-usb|debootstrap|chroot.*configure-system)" | \
                           grep -v grep | \
                           awk '{print $2}' | \
                           grep -v "^${current_pid}$" | \
                           grep -v "^${parent_pid}$")
        
        if [ -n "$stuck_pids" ]; then
            log "  Found stuck processes: $stuck_pids"
            for pid in $stuck_pids; do
                if kill -0 $pid 2>/dev/null; then
                    log "    Killing process $pid"
                    kill -TERM $pid 2>/dev/null || true
                    sleep 1
                    kill -KILL $pid 2>/dev/null || true
                    cleanup_performed=true
                fi
            done
        fi
    }
    
    # Unmount any mounted filesystems under /mnt/usb
    cleanup_mounted_filesystems() {
        log "  Checking for mounted filesystems..."
        
        # Get all mounts under /mnt/usb in reverse order (deepest first)
        local mounts=$(mount | grep "/mnt/usb" | awk '{print $3}' | sort -r)
        
        if [ -n "$mounts" ]; then
            log "  Found mounted filesystems under /mnt/usb"
            for mount_point in $mounts; do
                log "    Unmounting $mount_point"
                umount -f "$mount_point" 2>/dev/null || umount -l "$mount_point" 2>/dev/null || true
                cleanup_performed=true
            done
        fi
    }
    
    # Clean up loop devices
    cleanup_loop_devices() {
        log "  Checking for loop devices..."
        
        # Find loop devices associated with media-bridge images
        local loop_devices=$(losetup -a | grep -E "(media-bridge|loop.*\.img)" | cut -d: -f1)
        
        if [ -n "$loop_devices" ]; then
            log "  Found loop devices to clean"
            for loop_dev in $loop_devices; do
                log "    Cleaning loop device $loop_dev"
                
                # First, clean any kpartx mappings
                if command -v kpartx >/dev/null 2>&1; then
                    kpartx -d "$loop_dev" 2>/dev/null || true
                fi
                
                # Detach the loop device
                losetup -d "$loop_dev" 2>/dev/null || true
                cleanup_performed=true
            done
        fi
        
        # Clean device mapper entries
        if [ -d /dev/mapper ]; then
            local dm_devices=$(ls /dev/mapper/ | grep -E "loop[0-9]+p[0-9]+" || true)
            if [ -n "$dm_devices" ]; then
                log "  Cleaning device mapper entries"
                for dm_dev in $dm_devices; do
                    log "    Removing /dev/mapper/$dm_dev"
                    dmsetup remove "/dev/mapper/$dm_dev" 2>/dev/null || true
                    cleanup_performed=true
                done
            fi
        fi
    }
    
    # Clean up temporary files and incomplete images
    cleanup_temp_files() {
        log "  Checking for temporary build files..."
        
        # Remove incomplete or temporary image files in current directory
        if [ -f "media-bridge.img.tmp" ] || [ -f "media-bridge.img.incomplete" ]; then
            log "  Removing incomplete image files"
            rm -f media-bridge.img.tmp media-bridge.img.incomplete 2>/dev/null || true
            cleanup_performed=true
        fi
        
        # Clean build logs that are too old (older than 7 days)
        if [ -d "build-logs" ]; then
            local old_logs=$(find build-logs -type f -name "*.log" -mtime +7 2>/dev/null || true)
            if [ -n "$old_logs" ]; then
                log "  Cleaning old build logs (>7 days)"
                echo "$old_logs" | xargs rm -f 2>/dev/null || true
                cleanup_performed=true
            fi
        fi
    }
    
    # Execute cleanup functions
    cleanup_stuck_processes
    cleanup_mounted_filesystems
    cleanup_loop_devices
    cleanup_temp_files
    
    if [ "$cleanup_performed" = true ]; then
        log "  Cleanup completed successfully"
    else
        log "  No cleanup needed - system is clean"
    fi
    
    # Small delay to ensure everything is properly cleaned
    sleep 1
}

# Export the function so it can be used by the main build script
export -f perform_build_cleanup