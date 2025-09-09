#!/bin/bash
# Install helper scripts module

install_helper_scripts() {
    log "Installing helper scripts..."
    
    # Copy all helper scripts to the target system
    local HELPER_DIR="$(dirname "$0")/helper-scripts"
    
    if [ -d "$HELPER_DIR" ]; then
        # Copy all helper scripts
        cp -r "$HELPER_DIR"/* /mnt/usb/usr/local/bin/
        
        # Make executable
        chmod +x /mnt/usb/usr/local/bin/media-bridge-*
        chmod +x /mnt/usb/usr/local/bin/ndi-display-*
        
        # Install PipeWire verification script (for build verification)
        if [ -f "$HELPER_DIR/media-bridge-verify-pipewire" ]; then
            cp "$HELPER_DIR/media-bridge-verify-pipewire" /mnt/usb/usr/local/bin/
            chmod +x /mnt/usb/usr/local/bin/media-bridge-verify-pipewire
            log "PipeWire verification script installed"
        fi
        
        # Copy Media Bridge intercom scripts and service (PipeWire only)
        if [ -f "$HELPER_DIR/media-bridge-intercom-pipewire" ]; then
            cp "$HELPER_DIR/media-bridge-intercom-pipewire" /mnt/usb/usr/local/bin/media-bridge-intercom
            chmod +x /mnt/usb/usr/local/bin/media-bridge-intercom
        fi
        
        # Copy launcher (fixed version for mediabridge user)
        if [ -f "$HELPER_DIR/media-bridge-intercom-fixed" ]; then
            cp "$HELPER_DIR/media-bridge-intercom-fixed" /mnt/usb/usr/local/bin/media-bridge-intercom-launcher
            chmod +x /mnt/usb/usr/local/bin/media-bridge-intercom-launcher
        elif [ -f "$HELPER_DIR/media-bridge-intercom-launcher-isolated" ]; then
            cp "$HELPER_DIR/media-bridge-intercom-launcher-isolated" /mnt/usb/usr/local/bin/media-bridge-intercom-launcher
            chmod +x /mnt/usb/usr/local/bin/media-bridge-intercom-launcher
        fi
        
        # Copy intercom control and config scripts (no API script anymore)
        for script in media-bridge-intercom-control media-bridge-intercom-config media-bridge-intercom-status media-bridge-intercom-logs media-bridge-intercom-restart media-bridge-intercom-monitor; do
            if [ -f "$HELPER_DIR/$script" ]; then
                cp "$HELPER_DIR/$script" /mnt/usb/usr/local/bin/
                chmod +x /mnt/usb/usr/local/bin/$script
            fi
        done
        
        # Install audio manager and cleanup scripts
        if [ -f "$HELPER_DIR/media-bridge-audio-manager" ]; then
            cp "$HELPER_DIR/media-bridge-audio-manager" /mnt/usb/usr/local/bin/
            chmod +x /mnt/usb/usr/local/bin/media-bridge-audio-manager
            log "Audio manager installed"
        fi
        
        if [ -f "$HELPER_DIR/media-bridge-audio-cleanup" ]; then
            cp "$HELPER_DIR/media-bridge-audio-cleanup" /mnt/usb/usr/local/bin/
            chmod +x /mnt/usb/usr/local/bin/media-bridge-audio-cleanup
            log "Audio cleanup script installed"
        fi
        
        if [ -f "$HELPER_DIR/media-bridge-audio-manager.service" ]; then
            cp "$HELPER_DIR/media-bridge-audio-manager.service" /mnt/usb/etc/systemd/system/
        fi
        
        # Install permission manager for strict audio isolation
        if [ -f "$HELPER_DIR/media-bridge-permission-manager" ]; then
            cp "$HELPER_DIR/media-bridge-permission-manager" /mnt/usb/usr/local/bin/
            chmod +x /mnt/usb/usr/local/bin/media-bridge-permission-manager
            log "Permission manager installed for audio isolation"
        fi
        
        if [ -f "$HELPER_DIR/media-bridge-permission-manager.service" ]; then
            cp "$HELPER_DIR/media-bridge-permission-manager.service" /mnt/usb/etc/systemd/system/
        fi
        
        if [ -f "$HELPER_DIR/media-bridge-intercom.service" ]; then
            cp "$HELPER_DIR/media-bridge-intercom.service" /mnt/usb/etc/systemd/system/
        fi
        
        # Install system-wide PipeWire services
        if [ -f "$HELPER_DIR/pipewire-system.service" ]; then
            cp "$HELPER_DIR/pipewire-system.service" /mnt/usb/etc/systemd/system/
        fi
        if [ -f "$HELPER_DIR/pipewire-system.socket" ]; then
            cp "$HELPER_DIR/pipewire-system.socket" /mnt/usb/etc/systemd/system/
        fi
        if [ -f "$HELPER_DIR/pipewire-pulse-system.service" ]; then
            cp "$HELPER_DIR/pipewire-pulse-system.service" /mnt/usb/etc/systemd/system/
        fi
        if [ -f "$HELPER_DIR/wireplumber-system.service" ]; then
            cp "$HELPER_DIR/wireplumber-system.service" /mnt/usb/etc/systemd/system/
        fi
        
        # Install PipeWire configuration
        if [ -f "$HELPER_DIR/pipewire-system.conf" ]; then
            mkdir -p /mnt/usb/etc/pipewire
            cp "$HELPER_DIR/pipewire-system.conf" /mnt/usb/etc/pipewire/
        fi
        if [ -d "$HELPER_DIR/pipewire-conf.d" ]; then
            mkdir -p /mnt/usb/etc/pipewire/pipewire.conf.d
            cp "$HELPER_DIR/pipewire-conf.d"/*.conf /mnt/usb/etc/pipewire/pipewire.conf.d/
        fi
        
        # Install WirePlumber configuration
        if [ -d "$HELPER_DIR/wireplumber-conf.d" ]; then
            mkdir -p /mnt/usb/etc/wireplumber/main.lua.d
            cp "$HELPER_DIR/wireplumber-conf.d"/*.lua /mnt/usb/etc/wireplumber/main.lua.d/
        fi
        
        # Install Chrome isolation rules
        if [ -f "$HELPER_DIR/wireplumber-chrome-isolation.lua" ]; then
            cp "$HELPER_DIR/wireplumber-chrome-isolation.lua" /mnt/usb/etc/wireplumber/main.lua.d/90-chrome-isolation.lua
            log "Chrome isolation rules installed"
        fi
        
        # Install audio manager
        if [ -f "$HELPER_DIR/media-bridge-audio-manager" ]; then
            cp "$HELPER_DIR/media-bridge-audio-manager" /mnt/usb/usr/local/bin/
            chmod +x /mnt/usb/usr/local/bin/media-bridge-audio-manager
        fi
        
        # Install mediabridge user setup script
        if [ -f "$HELPER_DIR/setup-mediabridge-user" ]; then
            cp "$HELPER_DIR/setup-mediabridge-user" /mnt/usb/usr/local/bin/
            chmod +x /mnt/usb/usr/local/bin/setup-mediabridge-user
        fi
        
        # Install ALSA device loader for when WirePlumber is unavailable
        if [ -f "$HELPER_DIR/load-alsa-devices.sh" ]; then
            cp "$HELPER_DIR/load-alsa-devices.sh" /mnt/usb/usr/local/bin/
            chmod +x /mnt/usb/usr/local/bin/load-alsa-devices.sh
        fi
        
        # Install WirePlumber headless configuration
        if [ -f "$HELPER_DIR/wireplumber-headless.conf" ]; then
            mkdir -p /mnt/usb/etc/wireplumber/wireplumber.conf.d
            cp "$HELPER_DIR/wireplumber-headless.conf" /mnt/usb/etc/wireplumber/wireplumber.conf.d/99-headless.conf
        fi
        
        
        # Setup Chrome profile with VDO.Ninja permissions (pre-granted)
        mkdir -p /mnt/usb/opt/chrome-vdo-profile/Default
        cat > /mnt/usb/opt/chrome-vdo-profile/Default/Preferences << 'PREFS'
{
  "profile": {
    "content_settings": {
      "exceptions": {
        "media_stream_mic": {
          "https://vdo.ninja:443,*": {
            "last_modified": "13400766142668061",
            "setting": 1
          }
        },
        "media_stream_camera": {
          "https://vdo.ninja:443,*": {
            "last_modified": "13400766150219890",
            "setting": 1
          }
        }
      }
    }
  },
  "browser": {
    "check_default_browser": false
  }
}
PREFS
        
        # Chrome intercom is now fully installed during build
        log "Chrome intercom scripts installed"
    else
        warn "Helper scripts directory not found, creating inline..."
        # If helper scripts directory doesn't exist, create them inline
        # This is a fallback for backward compatibility
        create_inline_helper_scripts
    fi
    
    # Copy test suite to the image
    log "Installing test suite..."
    local TEST_DIR="$(dirname "$0")/../tests"
    
    if [ -d "$TEST_DIR" ]; then
        # Create test directory on target
        mkdir -p /mnt/usb/opt/media-bridge-tests
        
        # Copy all test files
        cp -r "$TEST_DIR"/* /mnt/usb/opt/media-bridge-tests/
        
        # Make test scripts executable
        find /mnt/usb/opt/media-bridge-tests -name "*.sh" -exec chmod +x {} \;
        
        log "Test suite installed to /opt/media-bridge-tests"
    else
        log "Warning: Test suite not found at $TEST_DIR"
    fi
}

create_inline_helper_scripts() {
    # This function creates helper scripts inline if the separate files don't exist
    # For backward compatibility with the original monolithic script
    
    # We'll include minimal versions here
    cat > /mnt/usb/usr/local/bin/media-bridge-help << 'EOF'
#!/bin/bash
echo "Media Bridge Commands:"
echo "  media-bridge-info      - Display system status"
echo "  media-bridge-set-name  - Set device name"
echo "  media-bridge-logs      - View logs"
echo "  media-bridge-update    - Update binary"
echo "  media-bridge-netstat   - Network status"
echo "  media-bridge-netmon    - Network monitor"
echo "  media-bridge-timesync  - Time synchronization status"
echo "  media-bridge-web       - Web interface control"
EOF
    chmod +x /mnt/usb/usr/local/bin/media-bridge-help

    # Create comprehensive time synchronization status script
    cat > /mnt/usb/usr/local/bin/media-bridge-timesync << 'EOFTIMESYNC'
#!/bin/bash
# Media Bridge Time Synchronization Status

clear
echo -e "\033[1;36m╔═════════════════════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;36m║                   Media Bridge Time Synchronization Status              ║\033[0m"
echo -e "\033[1;36m╚═════════════════════════════════════════════════════════════════════════╝\033[0m"
echo ""

# System Time Information
echo -e "\033[1;32mSystem Time Information:\033[0m"
echo "  Current Time: $(date)"
echo "  Timezone:     $(timedatectl status | grep 'Time zone' | cut -d: -f2 | xargs)"
echo "  Uptime:       $(uptime -p)"
echo ""

# PTP4L Status
echo -e "\033[1;32mPTP (Precision Time Protocol) Status:\033[0m"
if systemctl is-active ptp4l >/dev/null 2>&1; then
    echo -e "  Service Status: \033[1;32mRunning\033[0m"
    
    # Get recent PTP logs
    PTP_LOGS=$(journalctl -u ptp4l -n 10 --no-pager -o cat 2>/dev/null)
    
    if echo "$PTP_LOGS" | grep -q "LISTENING"; then
        echo -e "  PTP State:      \033[1;33mLISTENING\033[0m (client-only mode, no master found)"
        echo "  Description:    Waiting for PTP master on network"
    elif echo "$PTP_LOGS" | grep -q "SLAVE"; then
        echo -e "  PTP State:      \033[1;32mSLAVE\033[0m (synchronized to master)"
        # Try to extract offset information
        OFFSET_INFO=$(echo "$PTP_LOGS" | grep "offset" | tail -1)
        if [ -n "$OFFSET_INFO" ]; then
            echo "  Last Offset:    $OFFSET_INFO"
        fi
    elif echo "$PTP_LOGS" | grep -q "MASTER"; then
        echo -e "  PTP State:      \033[1;31mMASTER\033[0m (ERROR: should be client-only)"
        echo "  Description:    Configuration error - acting as master instead of client"
    else
        echo -e "  PTP State:      \033[1;33mUNKNOWN\033[0m"
    fi
    
    # Interface information
    echo "  Interface:      eth0"
    echo "  Transport:      UDPv4"
    echo "  Domain:         0"
    
    # Show recent log entries
    echo ""
    echo "  Recent PTP Log Entries:"
    echo "$PTP_LOGS" | tail -5 | sed 's/^/    /'
else
    echo -e "  Service Status: \033[1;31mStopped\033[0m"
fi

echo ""

# PHC2SYS Status
echo -e "\033[1;32mPHC2SYS (Hardware Clock Sync) Status:\033[0m"
if systemctl is-active phc2sys >/dev/null 2>&1; then
    echo -e "  Service Status: \033[1;32mRunning\033[0m"
elif systemctl is-failed phc2sys >/dev/null 2>&1; then
    echo -e "  Service Status: \033[1;33mNot Required\033[0m (software timestamping mode)"
    echo "  Description:    PHC2SYS not needed when using software timestamps"
else
    echo -e "  Service Status: \033[1;31mStopped\033[0m"
fi

echo ""

# NTP/Chrony Status
echo -e "\033[1;32mNTP (Network Time Protocol) Status:\033[0m"
if systemctl is-active chrony >/dev/null 2>&1; then
    echo -e "  Service Status: \033[1;32mRunning\033[0m"
    
    if command -v chronyc >/dev/null 2>&1; then
        # Get detailed tracking information
        TRACKING=$(chronyc tracking 2>/dev/null)
        
        if [ -n "$TRACKING" ]; then
            echo ""
            echo "  Detailed NTP Tracking:"
            
            REF_ID=$(echo "$TRACKING" | grep "Reference ID" | cut -d: -f2 | xargs)
            STRATUM=$(echo "$TRACKING" | grep "Stratum" | cut -d: -f2 | xargs)
            SYSTEM_TIME=$(echo "$TRACKING" | grep "System time" | cut -d: -f2 | xargs)
            LAST_OFFSET=$(echo "$TRACKING" | grep "Last offset" | cut -d: -f2 | xargs)
            RMS_OFFSET=$(echo "$TRACKING" | grep "RMS offset" | cut -d: -f2 | xargs)
            FREQUENCY=$(echo "$TRACKING" | grep "Frequency" | cut -d: -f2 | xargs)
            
            if [ "$REF_ID" = "7F7F0101 ()" ]; then
                echo -e "    Reference:      \033[1;33mLocal Clock\033[0m (no external NTP sources)"
                echo "    Status:         Free-running (no network time sync)"
            else
                echo -e "    Reference ID:   \033[1;32m$REF_ID\033[0m"
                echo "    Status:         Synchronized to external NTP"
            fi
            
            echo "    Stratum:        $STRATUM"
            echo "    System Offset:  $SYSTEM_TIME"
            echo "    Last Offset:    $LAST_OFFSET"
            echo "    RMS Offset:     $RMS_OFFSET"
            echo "    Frequency:      $FREQUENCY"
        fi
        
        # Show NTP sources
        SOURCES=$(chronyc sources 2>/dev/null)
        if [ -n "$SOURCES" ] && ! echo "$SOURCES" | grep -q "^$"; then
            echo ""
            echo "  NTP Sources:"
            echo "$SOURCES" | sed 's/^/    /'
        fi
    fi
else
    echo -e "  Service Status: \033[1;31mStopped\033[0m"
fi

echo ""

# System Clock Synchronization
echo -e "\033[1;32mSystem Clock Synchronization:\033[0m"
TIMEDATECTL_OUTPUT=$(timedatectl status 2>/dev/null)
if [ -n "$TIMEDATECTL_OUTPUT" ]; then
    if echo "$TIMEDATECTL_OUTPUT" | grep -q "System clock synchronized: yes"; then
        echo -e "  Status: \033[1;32mSynchronized\033[0m"
    else
        echo -e "  Status: \033[1;33mNot Synchronized\033[0m"
    fi
    
    NTP_SERVICE=$(echo "$TIMEDATECTL_OUTPUT" | grep "NTP service" | cut -d: -f2 | xargs)
    echo "  NTP Service: $NTP_SERVICE"
fi

echo ""

# Time Accuracy Summary
echo -e "\033[1;32mTime Accuracy Summary:\033[0m"
if command -v chronyc >/dev/null 2>&1; then
    RMS_OFFSET=$(chronyc tracking 2>/dev/null | grep "RMS offset" | awk '{print $4}')
    if [ -n "$RMS_OFFSET" ] && [ "$RMS_OFFSET" != "0.000000000" ]; then
        # Convert to more readable units
        if echo "$RMS_OFFSET" | grep -q "e-"; then
            echo -e "  Estimated Accuracy: \033[1;32m< 1 microsecond\033[0m (excellent)"
        elif [ "$(echo "$RMS_OFFSET" | cut -d. -f1)" = "0" ]; then
            # Less than 1 second
            MS_OFFSET=$(echo "$RMS_OFFSET * 1000" | bc 2>/dev/null | cut -d. -f1)
            if [ -n "$MS_OFFSET" ] && [ "$MS_OFFSET" -lt 100 ]; then
                echo -e "  Estimated Accuracy: \033[1;32m±${MS_OFFSET}ms\033[0m (good)"
            else
                echo -e "  Estimated Accuracy: \033[1;33m±$RMS_OFFSET seconds\033[0m"
            fi
        else
            echo -e "  Estimated Accuracy: \033[1;33m±$RMS_OFFSET seconds\033[0m"
        fi
    else
        echo "  Estimated Accuracy: Unknown"
    fi
else
    echo "  Accuracy information not available"
fi

echo ""
echo -e "\033[1;36mTime Sync Recommendations:\033[0m"
echo "  • For best accuracy: Connect to network with PTP master"
echo "  • For good accuracy: Ensure internet access for NTP"
echo "  • Current mode: PTP client-only with NTP fallback"
echo ""
echo "Commands: journalctl -u ptp4l, journalctl -u chrony, chronyc sources"
EOFTIMESYNC
    chmod +x /mnt/usb/usr/local/bin/media-bridge-timesync
}

export -f install_helper_scripts create_inline_helper_scripts