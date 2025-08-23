#!/bin/bash
# Time synchronization test suite
# Tests PTP, NTP, and coordinator service

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Time Sync Test Suite"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Test 1: Time sync coordinator service
log_test "Test 1: Time sync coordinator service"

coordinator_status=$(box_ssh "systemctl is-active time-sync-coordinator" | tr -d '\n')
if [ "$coordinator_status" = "active" ]; then
    record_test "Coordinator Service" "PASS" "Time sync coordinator active"
else
    record_test "Coordinator Service" "FAIL" "Coordinator not active"
fi

# Test 2: PTP (Precision Time Protocol) status
log_test "Test 2: PTP status"

# Check ptp4l service
ptp4l_status=$(box_ssh "systemctl is-active ptp4l" | tr -d '\n')
if [ "$ptp4l_status" = "active" ]; then
    record_test "PTP4L Service" "PASS" "PTP4L daemon active"
    
    # Check if PTP is actually syncing
    ptp_sync_check=$(box_ssh "journalctl -u ptp4l -n 20 --no-pager | grep -c 'master offset' || echo 0")
    if [ "$ptp_sync_check" -gt 0 ]; then
        record_test "PTP Synchronization" "PASS" "PTP is synchronizing"
        
        # Get offset information
        ptp_offset=$(box_ssh "journalctl -u ptp4l -n 5 --no-pager | grep 'master offset' | tail -1 | grep -oE 'offset[[:space:]]+[-0-9]+' | awk '{print \$2}'")
        if [ -n "$ptp_offset" ]; then
            log_info "PTP offset: ${ptp_offset} ns"
            
            # Check if offset is reasonable (within 1ms = 1000000ns)
            offset_abs=${ptp_offset#-}  # Remove negative sign if present
            if [ "$offset_abs" -lt 1000000 ]; then
                record_test "PTP Accuracy" "PASS" "Offset within 1ms: ${ptp_offset}ns"
            else
                record_test "PTP Accuracy" "WARN" "Large offset: ${ptp_offset}ns"
            fi
        fi
    else
        record_test "PTP Synchronization" "FAIL" "PTP not synchronizing"
    fi
else
    record_test "PTP4L Service" "INFO" "PTP not active (may be using NTP)"
fi

# Check phc2sys service (syncs PTP hardware clock to system clock)
phc2sys_status=$(box_ssh "systemctl is-active phc2sys" | tr -d '\n')
if [ "$phc2sys_status" = "active" ] || [ "$phc2sys_status" = "activating" ]; then
    record_test "PHC2SYS Service" "PASS" "Hardware clock sync active/starting"
else
    record_test "PHC2SYS Service" "INFO" "PHC2SYS not active"
fi

# Test 3: NTP (Network Time Protocol) status
log_test "Test 3: NTP status"

# Check systemd-timesyncd (NTP client)
timesyncd_status=$(box_ssh "systemctl is-active systemd-timesyncd" | tr -d '\n')
if [ "$timesyncd_status" = "active" ]; then
    record_test "NTP Service" "PASS" "systemd-timesyncd active"
    
    # Check NTP sync status
    ntp_sync=$(box_ssh "timedatectl status | grep 'System clock synchronized' | awk '{print \$4}'" | tr -d '\n')
    if [ "$ntp_sync" = "yes" ]; then
        record_test "NTP Synchronization" "PASS" "Clock synchronized via NTP"
        
        # Get NTP server info
        ntp_server=$(box_ssh "timedatectl show-timesync --property=ServerName --value 2>/dev/null" | tr -d '\n')
        if [ -n "$ntp_server" ]; then
            log_info "NTP server: $ntp_server"
        fi
    else
        record_test "NTP Synchronization" "WARN" "NTP not synchronized"
    fi
else
    record_test "NTP Service" "INFO" "systemd-timesyncd not active"
fi

# Test 4: Overall time sync status
log_test "Test 4: Overall time synchronization"

sync_status=$(box_get_time_sync_status)
log_output "Time Sync Status" "$sync_status"

if assert_time_synchronized; then
    record_test "Time Synchronization" "PASS"
    
    # Determine primary source
    if echo "$sync_status" | grep -q "PTP (Primary)"; then
        record_test "Primary Time Source" "PASS" "Using PTP (best quality)"
    elif echo "$sync_status" | grep -q "NTP (Fallback)"; then
        record_test "Primary Time Source" "PASS" "Using NTP (fallback)"
    else
        record_test "Primary Time Source" "FAIL" "No time source active"
    fi
else
    record_test "Time Synchronization" "FAIL" "Time not synchronized"
fi

# Test 5: System time accuracy
log_test "Test 5: System time accuracy"

# Get system time
system_time=$(box_ssh "date '+%Y-%m-%d %H:%M:%S %Z'")
log_info "System time: $system_time"

# Check if timezone is set correctly
timezone=$(box_ssh "timedatectl show --property=Timezone --value" | tr -d '\n')
if [ -n "$timezone" ]; then
    record_test "Timezone Configuration" "PASS" "Timezone: $timezone"
else
    record_test "Timezone Configuration" "WARN" "Timezone not configured"
fi

# Check RTC (hardware clock)
rtc_time=$(box_ssh "hwclock -r 2>/dev/null || echo 'No RTC'")
if [ "$rtc_time" != "No RTC" ]; then
    log_info "RTC time: $rtc_time"
    record_test "Hardware Clock" "PASS" "RTC present and readable"
else
    record_test "Hardware Clock" "INFO" "No hardware clock available"
fi

# Test 6: Failover mechanism
log_test "Test 6: Time sync failover"

# Check coordinator logs for failover events
failover_logs=$(box_ssh "journalctl -u time-sync-coordinator -n 50 --no-pager | grep -E 'Switching|Failed|Fallback' | tail -5")
if [ -n "$failover_logs" ]; then
    log_info "Recent failover events:"
    echo "$failover_logs"
    record_test "Failover Mechanism" "INFO" "Failover events detected in logs"
else
    record_test "Failover Mechanism" "INFO" "No recent failover events"
fi

# Test 7: Time sync impact on services
log_test "Test 7: Time sync impact on services"

# Check if NDI services are affected by time sync
ndi_time_errors=$(box_ssh "journalctl -u ndi-bridge -n 100 --no-pager | grep -iE 'time|clock|sync' | grep -iE 'error|fail' | wc -l")
if [ "$ndi_time_errors" -eq 0 ]; then
    record_test "NDI Time Stability" "PASS" "No time-related errors in NDI service"
else
    record_test "NDI Time Stability" "WARN" "$ndi_time_errors time-related errors found"
fi

# Test 8: PTP network detection
log_test "Test 8: PTP network detection"

# Check for PTP master on network
ptp_masters=$(box_ssh "timeout 5 ptp4l -m -q -i eth0 2>&1 | grep -c 'master' || echo 0" 2>/dev/null)
if [ "$ptp_masters" -gt 0 ]; then
    record_test "PTP Master Detection" "PASS" "PTP master found on network"
else
    record_test "PTP Master Detection" "INFO" "No PTP master detected on network"
fi

# Test 9: Time drift monitoring
log_test "Test 9: Time drift monitoring"

# Get current offset/drift information
if [ "$timesyncd_status" = "active" ]; then
    time_stats=$(box_ssh "timedatectl timesync-status 2>/dev/null || echo 'Not available'")
    if [ "$time_stats" != "Not available" ]; then
        log_output "Time Sync Statistics" "$time_stats"
        
        # Extract offset if available
        offset=$(echo "$time_stats" | grep -i offset | head -1)
        if [ -n "$offset" ]; then
            record_test "Time Offset" "INFO" "$offset"
        fi
    fi
fi

# Test 10: Configuration files
log_test "Test 10: Time sync configuration"

# Check PTP configuration
ptp_config=$(box_ssh "[ -f /etc/ptp4l.conf ] && echo 'exists' || echo 'missing'")
if [ "$ptp_config" = "exists" ]; then
    record_test "PTP Configuration" "PASS" "/etc/ptp4l.conf exists"
    
    # Check key settings
    ptp_interface=$(box_ssh "grep -E '^[[:space:]]*\\[' /etc/ptp4l.conf 2>/dev/null | head -1")
    if [ -n "$ptp_interface" ]; then
        log_info "PTP interface config: $ptp_interface"
    fi
else
    record_test "PTP Configuration" "INFO" "No PTP config file"
fi

# Check NTP configuration
ntp_config=$(box_ssh "[ -f /etc/systemd/timesyncd.conf ] && echo 'exists' || echo 'missing'")
if [ "$ntp_config" = "exists" ]; then
    record_test "NTP Configuration" "PASS" "/etc/systemd/timesyncd.conf exists"
    
    # Check for custom NTP servers
    ntp_servers=$(box_ssh "grep '^NTP=' /etc/systemd/timesyncd.conf 2>/dev/null")
    if [ -n "$ntp_servers" ]; then
        log_info "Custom NTP servers: $ntp_servers"
    fi
else
    record_test "NTP Configuration" "INFO" "Using default NTP configuration"
fi

# Collect diagnostic information
log_info "Collecting time sync diagnostics..."

# Get coordinator status
coordinator_logs=$(box_ssh "journalctl -u ndi-bridge-timesync-coordinator -n 20 --no-pager")
log_output "Coordinator Recent Logs" "$coordinator_logs"

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All time sync tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED time sync tests failed"
    exit 1
fi