#!/bin/bash
# NDI Display service configuration module - Single stream per display design

configure_ndi_display_service() {
    log "Configuring NDI Display service (single-stream design)..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFNDIDISPLAY'

# Install DRM/KMS libraries for display output
apt-get install -y --no-install-recommends \
    libdrm2 \
    libdrm-dev \
    libgbm1 \
    libgl1-mesa-dri \
    libgl1-mesa-glx \
    mesa-utils

# Create ndi-bridge user if it doesn't exist
if ! id -u ndi-bridge >/dev/null 2>&1; then
    useradd -r -s /bin/false -d /var/lib/ndi-bridge -m ndi-bridge
    usermod -a -G video,audio,render ndi-bridge
fi

# Create NDI Display configuration directory
mkdir -p /etc/ndi-bridge
chown -R ndi-bridge:ndi-bridge /etc/ndi-bridge

# Create runtime directory for status files
mkdir -p /var/run/ndi-display
chown ndi-bridge:ndi-bridge /var/run/ndi-display

# Default display policy configuration
cat > /etc/ndi-bridge/display-policy.conf << 'EOFPOLICY'
# NDI Display Policy Configuration
# 
# This file controls how displays are allocated between
# Linux console and NDI display outputs

# Which display should keep the console (-1 for none)
# Default: 0 (Display 0/HDMI-1 reserved for console)
CONSOLE_DISPLAY=0

# If the console display is needed for NDI, should we
# automatically move console to another free display?
# Default: true
CONSOLE_FALLBACK=true

# Allow all displays to be used for NDI (no console)?
# WARNING: Setting this to true means you may lose local
# console access! Make sure SSH is working first!
# Default: false
ALLOW_NO_CONSOLE=false

# Enable emergency console recovery via keyboard shortcut
# Pressing Ctrl+Alt+F12 will stop all NDI displays and
# restore console to display 0
# Default: true
EMERGENCY_RECOVERY=true
EOFPOLICY

# Install systemd template service for per-display instances
cat > /etc/systemd/system/ndi-display@.service << 'EOFSERVICE'
[Unit]
Description=NDI Display %i - Receive and display NDI stream on HDMI %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ndi-bridge
Group=video

# Load configuration for this display
EnvironmentFile=/etc/ndi-bridge/display-%i.conf

# Pre-start checks
ExecStartPre=/usr/local/bin/ndi-display-console-check %i

# Main service - stream name from config, display ID from instance
ExecStart=/opt/ndi-bridge/ndi-display "${STREAM_NAME}" %i

# Restart on failure
Restart=on-failure
RestartSec=5

# Resource limits
LimitNOFILE=65536
LimitRTPRIO=95
LimitMEMLOCK=infinity

# CPU scheduling for real-time video
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=80

# Allow access to display devices
SupplementaryGroups=video render
DeviceAllow=/dev/dri/card* rw
DeviceAllow=/dev/fb* rw

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ndi-display-%i

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Copy NDI Display binary
if [ -f /mnt/usb/ndi-display ]; then
    cp /mnt/usb/ndi-display /opt/ndi-bridge/
    chmod +x /opt/ndi-bridge/ndi-display
else
    log "Warning: ndi-display binary not found"
fi

# Helper Scripts Installation
# ============================

# ndi-display-status - Show status of all displays
cat > /usr/local/bin/ndi-display-status << 'EOFSTATUS'
#!/bin/bash
/opt/ndi-bridge/ndi-display status
EOFSTATUS
chmod +x /usr/local/bin/ndi-display-status

# ndi-display-list - List available NDI streams
cat > /usr/local/bin/ndi-display-list << 'EOFLIST'
#!/bin/bash
/opt/ndi-bridge/ndi-display list
EOFLIST
chmod +x /usr/local/bin/ndi-display-list

# ndi-display-show - Show stream on specific display
cat > /usr/local/bin/ndi-display-show << 'EOFSHOW'
#!/bin/bash

if [ $# -ne 2 ]; then
    echo "Usage: ndi-display-show <stream_name> <display_id>"
    echo "  display_id: 0, 1, or 2"
    exit 1
fi

STREAM_NAME="$1"
DISPLAY_ID="$2"

if ! [[ "$DISPLAY_ID" =~ ^[0-2]$ ]]; then
    echo "Error: Display ID must be 0, 1, or 2"
    exit 1
fi

# Create config file
cat > /etc/ndi-bridge/display-${DISPLAY_ID}.conf << EOF
STREAM_NAME="${STREAM_NAME}"
DISPLAY_ID=${DISPLAY_ID}
ENABLED=true
EOF

# Restart service
systemctl restart ndi-display@${DISPLAY_ID}
echo "Showing '${STREAM_NAME}' on display ${DISPLAY_ID}"
EOFSHOW
chmod +x /usr/local/bin/ndi-display-show

# ndi-display-stop - Stop NDI on specific display
cat > /usr/local/bin/ndi-display-stop << 'EOFSTOP'
#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: ndi-display-stop <display_id>"
    echo "  display_id: 0, 1, or 2"
    exit 1
fi

DISPLAY_ID="$1"

if ! [[ "$DISPLAY_ID" =~ ^[0-2]$ ]]; then
    echo "Error: Display ID must be 0, 1, or 2"
    exit 1
fi

systemctl stop ndi-display@${DISPLAY_ID}
systemctl disable ndi-display@${DISPLAY_ID} 2>/dev/null
rm -f /etc/ndi-bridge/display-${DISPLAY_ID}.conf
echo "Stopped NDI on display ${DISPLAY_ID}"
EOFSTOP
chmod +x /usr/local/bin/ndi-display-stop

# ndi-display-auto - Auto-configure displays (optional)
cat > /usr/local/bin/ndi-display-auto << 'EOFAUTO'
#!/bin/bash
echo "Auto-configuration not yet implemented"
echo "Use ndi-display-config <display_id> to configure individual displays"
EOFAUTO
chmod +x /usr/local/bin/ndi-display-auto

# ndi-display-config - Interactive configuration tool
cat > /usr/local/bin/ndi-display-config << 'EOFCONFIG'
#!/bin/bash
#
# Configure individual NDI display
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if running as root for service management
check_root() {
    if [ "$EUID" -ne 0 ] && [ "$1" = "apply" ]; then
        echo "Please run with sudo to apply configuration"
        exit 1
    fi
}

# Show usage
if [ $# -lt 1 ]; then
    echo "Usage: ndi-display-config <display-id>"
    echo "       ndi-display-config 0      # Configure display 0"
    echo "       ndi-display-config 1      # Configure display 1"
    echo "       ndi-display-config 2      # Configure display 2"
    echo ""
    echo "       ndi-display-config status # Show all displays status"
    exit 1
fi

# Handle status command
if [ "$1" = "status" ]; then
    /usr/local/bin/ndi-display-status
    exit 0
fi

DISPLAY_ID=$1

# Validate display ID
if ! [[ "$DISPLAY_ID" =~ ^[0-2]$ ]]; then
    echo -e "${RED}Error: Display ID must be 0, 1, or 2${NC}"
    exit 1
fi

CONFIG_FILE="/etc/ndi-bridge/display-${DISPLAY_ID}.conf"
POLICY_FILE="/etc/ndi-bridge/display-policy.conf"

# Create config directory if it doesn't exist
if [ ! -d /etc/ndi-bridge ]; then
    sudo mkdir -p /etc/ndi-bridge
fi

# Load current configuration
CURRENT_STREAM=""
ENABLED="false"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    CURRENT_STREAM="$STREAM_NAME"
fi

# Check console policy
CONSOLE_DISPLAY=0
if [ -f "$POLICY_FILE" ]; then
    source "$POLICY_FILE"
fi

# Check if display is currently running
SERVICE_STATUS="stopped"
if systemctl is-active --quiet ndi-display@${DISPLAY_ID}; then
    SERVICE_STATUS="running"
fi

# Show current status
echo -e "${CYAN}Configure Display ${DISPLAY_ID} (HDMI-$((DISPLAY_ID + 1)))${NC}"
echo "========================================"
echo ""

if [ "$DISPLAY_ID" = "$CONSOLE_DISPLAY" ]; then
    echo -e "${YELLOW}Note: This display is reserved for console${NC}"
    echo ""
fi

if [ -n "$CURRENT_STREAM" ]; then
    echo "Current configuration:"
    echo "  Stream: $CURRENT_STREAM"
    echo "  Service: $SERVICE_STATUS"
    echo ""
fi

# Check if console is active on this display
CONSOLE_ACTIVE=false
VTCON_PATH="/sys/class/vtconsole/vtcon${DISPLAY_ID}/bind"
if [ -f "$VTCON_PATH" ]; then
    if [ "$(cat $VTCON_PATH)" = "1" ]; then
        CONSOLE_ACTIVE=true
        echo -e "${YELLOW}Console is currently active on this display${NC}"
        echo ""
    fi
fi

# Show menu
echo "Available actions:"
echo "  1. Set NDI stream"
echo "  2. Clear configuration (disable)"
echo "  3. Keep as console display"
echo "  4. Show available NDI streams"
echo "  5. Exit"
echo ""

read -p "Select action (1-5): " ACTION

case "$ACTION" in
    1)
        # List available streams
        echo ""
        echo "Searching for NDI streams..."
        STREAMS=$(/opt/ndi-bridge/ndi-display list 2>/dev/null | grep -E "^[0-9]+:" || true)
        
        if [ -z "$STREAMS" ]; then
            echo -e "${RED}No NDI streams found${NC}"
            exit 1
        fi
        
        echo ""
        echo "Available NDI streams:"
        echo "----------------------"
        echo "$STREAMS"
        echo ""
        echo "Enter stream name exactly as shown above"
        echo "(or press Enter to cancel)"
        echo ""
        read -p "Stream name: " NEW_STREAM
        
        if [ -z "$NEW_STREAM" ]; then
            echo "Cancelled"
            exit 0
        fi
        
        # Confirm configuration
        echo ""
        echo "Configuration summary:"
        echo "  Display: ${DISPLAY_ID} (HDMI-$((DISPLAY_ID + 1)))"
        echo "  Stream: $NEW_STREAM"
        
        if [ "$CONSOLE_ACTIVE" = "true" ]; then
            echo -e "  ${YELLOW}Console will be disabled on this display${NC}"
        fi
        
        echo ""
        read -p "Apply this configuration? (y/n): " CONFIRM
        
        if [ "$CONFIRM" != "y" ]; then
            echo "Cancelled"
            exit 0
        fi
        
        # Write configuration
        check_root apply
        
        cat > "$CONFIG_FILE" << EOF
# NDI Display ${DISPLAY_ID} Configuration
STREAM_NAME="$NEW_STREAM"
DISPLAY_ID=${DISPLAY_ID}
ENABLED=true
EOF
        
        # Stop service if running
        if [ "$SERVICE_STATUS" = "running" ]; then
            echo "Stopping current stream..."
            sudo systemctl stop ndi-display@${DISPLAY_ID}
        fi
        
        # Disable console if needed
        if [ "$CONSOLE_ACTIVE" = "true" ]; then
            echo "Disabling console on display ${DISPLAY_ID}..."
            sudo /usr/local/bin/ndi-display-console-manager disable ${DISPLAY_ID}
        fi
        
        # Start service
        echo "Starting NDI display service..."
        sudo systemctl enable ndi-display@${DISPLAY_ID}
        sudo systemctl start ndi-display@${DISPLAY_ID}
        
        echo -e "${GREEN}Configuration applied successfully!${NC}"
        echo ""
        echo "Check status with: ndi-display-config status"
        ;;
        
    2)
        # Clear configuration
        check_root apply
        
        if [ "$SERVICE_STATUS" = "running" ]; then
            echo "Stopping NDI display service..."
            sudo systemctl stop ndi-display@${DISPLAY_ID}
        fi
        
        sudo systemctl disable ndi-display@${DISPLAY_ID} 2>/dev/null || true
        
        if [ -f "$CONFIG_FILE" ]; then
            sudo rm "$CONFIG_FILE"
        fi
        
        echo -e "${GREEN}Configuration cleared${NC}"
        ;;
        
    3)
        # Keep as console
        check_root apply
        
        if [ "$SERVICE_STATUS" = "running" ]; then
            echo "Stopping NDI display service..."
            sudo systemctl stop ndi-display@${DISPLAY_ID}
            sudo systemctl disable ndi-display@${DISPLAY_ID}
        fi
        
        if [ "$CONSOLE_ACTIVE" = "false" ]; then
            echo "Enabling console on display ${DISPLAY_ID}..."
            sudo /usr/local/bin/ndi-display-console-manager enable ${DISPLAY_ID}
        fi
        
        # Update policy file
        sudo sed -i "s/CONSOLE_DISPLAY=.*/CONSOLE_DISPLAY=${DISPLAY_ID}/" "$POLICY_FILE" 2>/dev/null || \
            echo "CONSOLE_DISPLAY=${DISPLAY_ID}" | sudo tee "$POLICY_FILE" > /dev/null
        
        echo -e "${GREEN}Display ${DISPLAY_ID} set as console display${NC}"
        ;;
        
    4)
        # Just show streams
        echo ""
        /usr/local/bin/ndi-display-list
        ;;
        
    5)
        echo "Exiting"
        exit 0
        ;;
        
    *)
        echo -e "${RED}Invalid selection${NC}"
        exit 1
        ;;
esac
EOFCONFIG
chmod +x /usr/local/bin/ndi-display-config

# ndi-display-console-check - Pre-start check for systemd
cat > /usr/local/bin/ndi-display-console-check << 'EOFCHECK'
#!/bin/bash
#
# Pre-start check for ndi-display service
# Ensures console is not active on the target display
#

DISPLAY_ID=$1

if [ -z "$DISPLAY_ID" ]; then
    echo "Error: Display ID not provided"
    exit 1
fi

# Check if console is active on this display
VTCON_PATH="/sys/class/vtconsole/vtcon${DISPLAY_ID}/bind"

if [ -f "$VTCON_PATH" ]; then
    if [ "$(cat $VTCON_PATH)" = "1" ]; then
        echo "Error: Console is active on display ${DISPLAY_ID}"
        echo "Run: sudo ndi-display-console-manager disable ${DISPLAY_ID}"
        exit 1
    fi
fi

# Check if display device exists
if [ ! -e "/dev/dri/card0" ] && [ ! -e "/dev/fb${DISPLAY_ID}" ]; then
    echo "Warning: No display device found for display ${DISPLAY_ID}"
    # Don't fail, as this might be normal in some setups
fi

exit 0
EOFCHECK
chmod +x /usr/local/bin/ndi-display-console-check

# ndi-display-console-manager - Manage console allocation
cat > /usr/local/bin/ndi-display-console-manager << 'EOFMANAGER'
#!/bin/bash
#
# Manage console allocation across displays
#

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Function to check if console is active on a display
is_console_active() {
    local display=$1
    local vtcon_path="/sys/class/vtconsole/vtcon${display}/bind"
    
    if [ -f "$vtcon_path" ]; then
        if [ "$(cat $vtcon_path)" = "1" ]; then
            return 0
        fi
    fi
    return 1
}

# Function to find an available display for console
find_free_display() {
    for i in 0 1 2; do
        # Skip the display we're trying to use
        if [ "$i" = "$1" ]; then
            continue
        fi
        
        # Check if NDI is running on this display
        if ! systemctl is-active --quiet ndi-display@${i}; then
            echo $i
            return 0
        fi
    done
    
    # No free display found
    echo -1
    return 1
}

case "$1" in
    status)
        echo "Console Status on Displays:"
        echo "==========================="
        for i in 0 1 2; do
            echo -n "Display $i: "
            if is_console_active $i; then
                echo "Console ACTIVE"
            else
                if systemctl is-active --quiet ndi-display@${i}; then
                    echo "NDI Display"
                else
                    echo "Inactive"
                fi
            fi
        done
        
        # Show framebuffer devices
        echo ""
        echo "Framebuffer devices:"
        ls -la /dev/fb* 2>/dev/null || echo "No framebuffer devices found"
        
        # Show DRM devices
        echo ""
        echo "DRM devices:"
        ls -la /dev/dri/card* 2>/dev/null || echo "No DRM devices found"
        ;;
        
    disable)
        if [ -z "$2" ]; then
            echo "Usage: $0 disable <display-id>"
            exit 1
        fi
        
        DISPLAY_ID=$2
        
        if ! [[ "$DISPLAY_ID" =~ ^[0-2]$ ]]; then
            echo "Error: Display ID must be 0, 1, or 2"
            exit 1
        fi
        
        if is_console_active $DISPLAY_ID; then
            echo "Disabling console on display $DISPLAY_ID..."
            
            # Find alternative display for console
            ALT_DISPLAY=$(find_free_display $DISPLAY_ID)
            
            if [ "$ALT_DISPLAY" -ge 0 ]; then
                echo "Moving console to display $ALT_DISPLAY..."
                
                # Enable console on alternative display first
                echo 1 > /sys/class/vtconsole/vtcon${ALT_DISPLAY}/bind 2>/dev/null || true
                
                # Then disable on requested display
                echo 0 > /sys/class/vtconsole/vtcon${DISPLAY_ID}/bind
                
                # Switch VT to the new display
                chvt 1
                
                echo "Console moved to display $ALT_DISPLAY"
            else
                # Check policy to see if we can disable all consoles
                ALLOW_NO_CONSOLE=false
                if [ -f /etc/ndi-bridge/display-policy.conf ]; then
                    source /etc/ndi-bridge/display-policy.conf
                fi
                
                if [ "$ALLOW_NO_CONSOLE" = "true" ]; then
                    echo "Warning: Disabling last console!"
                    echo 0 > /sys/class/vtconsole/vtcon${DISPLAY_ID}/bind
                    echo "Console disabled. SSH access required for recovery!"
                else
                    echo "Error: Cannot disable console - no alternative display available"
                    echo "To force, set ALLOW_NO_CONSOLE=true in /etc/ndi-bridge/display-policy.conf"
                    exit 1
                fi
            fi
        else
            echo "Console is not active on display $DISPLAY_ID"
        fi
        ;;
        
    enable)
        if [ -z "$2" ]; then
            echo "Usage: $0 enable <display-id>"
            exit 1
        fi
        
        DISPLAY_ID=$2
        
        if ! [[ "$DISPLAY_ID" =~ ^[0-2]$ ]]; then
            echo "Error: Display ID must be 0, 1, or 2"
            exit 1
        fi
        
        # Check if NDI is running on this display
        if systemctl is-active --quiet ndi-display@${DISPLAY_ID}; then
            echo "Error: NDI display service is running on display $DISPLAY_ID"
            echo "Stop it first with: systemctl stop ndi-display@${DISPLAY_ID}"
            exit 1
        fi
        
        if ! is_console_active $DISPLAY_ID; then
            echo "Enabling console on display $DISPLAY_ID..."
            echo 1 > /sys/class/vtconsole/vtcon${DISPLAY_ID}/bind
            
            # Switch to TTY1
            chvt 1
            
            echo "Console enabled on display $DISPLAY_ID"
        else
            echo "Console is already active on display $DISPLAY_ID"
        fi
        ;;
        
    move)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 move <from-display> <to-display>"
            exit 1
        fi
        
        FROM_DISPLAY=$2
        TO_DISPLAY=$3
        
        if ! [[ "$FROM_DISPLAY" =~ ^[0-2]$ ]] || ! [[ "$TO_DISPLAY" =~ ^[0-2]$ ]]; then
            echo "Error: Display IDs must be 0, 1, or 2"
            exit 1
        fi
        
        if [ "$FROM_DISPLAY" = "$TO_DISPLAY" ]; then
            echo "Error: Source and destination displays are the same"
            exit 1
        fi
        
        if ! is_console_active $FROM_DISPLAY; then
            echo "Error: Console is not active on display $FROM_DISPLAY"
            exit 1
        fi
        
        if systemctl is-active --quiet ndi-display@${TO_DISPLAY}; then
            echo "Error: NDI display service is running on display $TO_DISPLAY"
            exit 1
        fi
        
        echo "Moving console from display $FROM_DISPLAY to display $TO_DISPLAY..."
        
        # Enable on new display first
        echo 1 > /sys/class/vtconsole/vtcon${TO_DISPLAY}/bind
        
        # Then disable on old display
        echo 0 > /sys/class/vtconsole/vtcon${FROM_DISPLAY}/bind
        
        # Switch VT
        chvt 1
        
        echo "Console moved successfully"
        ;;
        
    emergency)
        echo "Emergency console recovery!"
        echo "=========================="
        
        # Stop all NDI displays
        echo "Stopping all NDI display services..."
        systemctl stop 'ndi-display@*'
        
        # Enable console on display 0
        echo "Enabling console on display 0..."
        echo 1 > /sys/class/vtconsole/vtcon0/bind
        
        # Disable console on other displays
        echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true
        echo 0 > /sys/class/vtconsole/vtcon2/bind 2>/dev/null || true
        
        # Switch to TTY1
        chvt 1
        
        echo "Console restored to display 0"
        echo "All NDI display services stopped"
        ;;
        
    *)
        echo "NDI Display Console Manager"
        echo "==========================="
        echo ""
        echo "Usage:"
        echo "  $0 status                    # Show console status"
        echo "  $0 disable <display-id>      # Disable console on display"
        echo "  $0 enable <display-id>       # Enable console on display"
        echo "  $0 move <from-id> <to-id>    # Move console between displays"
        echo "  $0 emergency                 # Emergency console recovery"
        exit 1
        ;;
esac
EOFMANAGER
chmod +x /usr/local/bin/ndi-display-console-manager

# Update help script to include NDI display commands
cat >> /usr/local/bin/ndi-bridge-help << 'EOFHELP'

# NDI Display Commands
echo -e "${CYAN}NDI Display Commands:${NC}"
echo "  ndi-display-status            - Show status of all displays"
echo "  ndi-display-list              - List available NDI streams"
echo "  ndi-display-config <id>       - Configure display (interactive)"
echo "  ndi-display-show <stream> <id> - Show stream on display"
echo "  ndi-display-stop <id>         - Stop NDI on display"
echo "  ndi-display-console-manager   - Manage console allocation"
EOFHELP

EOFNDIDISPLAY

    log "NDI Display service configuration complete"
}