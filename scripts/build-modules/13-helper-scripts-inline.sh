#!/bin/bash
# Create all helper scripts inline during chroot setup

create_all_helper_scripts() {
    log "Creating all helper scripts in chroot..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFHELPERS'

# Replace placeholders with actual values
sed -i "s/BUILD_TIMESTAMP_PLACEHOLDER/${BUILD_TIMESTAMP}/" /etc/ndi-bridge/build-timestamp
sed -i "s/BUILD_SCRIPT_VERSION_PLACEHOLDER/${BUILD_SCRIPT_VERSION}/" /etc/ndi-bridge/build-script-version

# Create all helper scripts
echo "Installing helper scripts..."

# ndi-bridge-info - matches welcome screen format
cat > /usr/local/bin/ndi-bridge-info << 'EOFINFOHELPER'
#!/bin/bash
# Display NDI Bridge system information in same format as welcome screen

clear
echo -e "\033[1;32m"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                      NDI Bridge System                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "\033[0m"
echo -e "\033[1;36mSystem Information:\033[0m"
echo "  Hostname:   $(hostname)"
IP_ADDR=$(ip -4 addr show dev br0 2>/dev/null | awk '/inet/ {print $2}' | cut -d/ -f1 | head -1)
if [ -z "$IP_ADDR" ]; then
    echo -e "  IP Address: \033[1;33mWaiting for DHCP...\033[0m"
else
    echo "  IP Address: $IP_ADDR"
fi
echo "  Uptime:     $(uptime -p)"
echo ""
echo -e "\033[1;36mSoftware Versions:\033[0m"
echo "  NDI-Bridge: $(/opt/ndi-bridge/ndi-bridge --version 2>&1 | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /[0-9]+\.[0-9]+\.[0-9]+/) print $i}' || echo 'Unknown')"
echo "  Build Script: $(cat /etc/ndi-bridge/build-script-version 2>/dev/null || echo 'Unknown')"
echo ""
echo -e "\033[1;36mNetwork Configuration:\033[0m"
echo "  • Both ethernet ports are bridged (br0)"
echo "  • Connect cable to either port"
echo "  • Chain devices through second port"
echo ""

# Additional detailed info
echo -e "\033[1;36mVideo Capture Device:\033[0m"
VIDEO_DEVICE=$(grep "^DEVICE=" /etc/ndi-bridge/config | cut -d'"' -f2)
if [ -e "$VIDEO_DEVICE" ]; then
    echo "  Device: $VIDEO_DEVICE \033[1;32m[PRESENT]\033[0m"
else
    echo "  Device: $VIDEO_DEVICE \033[1;31m[NOT FOUND]\033[0m"
fi
echo ""

echo -e "\033[1;36mService Status:\033[0m"
if systemctl is-active --quiet ndi-bridge; then
    echo -e "  NDI Bridge: \033[1;32m● Running\033[0m"
else
    echo -e "  NDI Bridge: \033[1;31m● Stopped\033[0m"
fi
echo ""

echo -e "\033[1;36mResource Usage:\033[0m"
echo "  Memory: $(free -h | awk '/^Mem:/ {print $3 " / " $2 " (" int($3/$2 * 100) "%)"}')"
echo "  CPU Load: $(uptime | awk -F'load average: ' '{print $2}')"
echo ""

echo -e "\033[1;36mNetwork Bridge Status:\033[0m"
for iface in $(ls /sys/class/net/br0/brif 2>/dev/null); do
    STATE=$(ip link show $iface | grep -q 'state UP' && echo -e "\033[1;32mUP\033[0m" || echo -e "\033[1;31mDOWN\033[0m")
    echo "  $iface: $STATE"
done
echo ""
EOFINFOHELPER
chmod +x /usr/local/bin/ndi-bridge-info

# ndi-bridge-set-name
cat > /usr/local/bin/ndi-bridge-set-name << 'EOFSETNAME'
#!/bin/bash
# NDI Bridge Device Name Setter
# Sets hostname, NDI name, and mDNS aliases
# Usage: ndi-bridge-set-name <simple-name>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "This script must be run as root"
fi

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <device-name>"
    echo "Example: $0 cam1"
    echo ""
    echo "This will set:"
    echo "  - Hostname to: ndi-bridge-cam1"
    echo "  - Short alias: cam1.local"
    echo "  - NDI name to: cam1"
    exit 1
fi

# Validate name (alphanumeric, dash, underscore only)
NEW_NAME="$1"
if ! [[ "$NEW_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Device name must contain only letters, numbers, dashes, and underscores"
fi

# Convert to lowercase for consistency
NEW_NAME=$(echo "$NEW_NAME" | tr '[:upper:]' '[:lower:]')

# Build full hostname
FULL_HOSTNAME="ndi-bridge-${NEW_NAME}"

log "Setting device name to: $NEW_NAME"
log "Full hostname will be: $FULL_HOSTNAME"
log "Short alias will be: ${NEW_NAME}.local"

# Remount root as read-write
mount -o remount,rw / 2>/dev/null || true

# Update hostname
echo "$FULL_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1 $FULL_HOSTNAME $NEW_NAME/" /etc/hosts

# Update NDI configuration
sed -i "s/NDI_NAME=.*/NDI_NAME=\"$NEW_NAME\"/" /etc/ndi-bridge/config

# Update Avahi configuration with new hostname
if [ -f /etc/avahi/avahi-daemon.conf ]; then
    sed -i "s/^host-name=.*/host-name=$FULL_HOSTNAME/" /etc/avahi/avahi-daemon.conf
fi

# Create Avahi alias service for short name
mkdir -p /etc/avahi/services
cat > /etc/avahi/services/ndi-bridge-alias.service << EOFALIAS
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>${NEW_NAME}</name>
  <service>
    <type>_device-info._tcp</type>
    <subtype>_ndi._sub._device-info._tcp</subtype>
    <port>0</port>
    <txt-record>model=NDI Bridge</txt-record>
    <txt-record>hostname=${FULL_HOSTNAME}</txt-record>
  </service>
</service-group>
EOFALIAS

# Update NDI service advertisement with actual NDI name
cat > /etc/avahi/services/ndi-bridge.service << EOFNDISERVICE
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>${NEW_NAME} (NDI)</name>
  <service>
    <type>_ndi._tcp</type>
    <port>5960</port>
    <txt-record>name=${NEW_NAME}</txt-record>
    <txt-record>groups=public</txt-record>
    <txt-record>model=NDI Bridge</txt-record>
  </service>
</service-group>
EOFNDISERVICE

# Update HTTP service advertisement with device name
cat > /etc/avahi/services/ndi-bridge-http.service << EOFHTTPSERVICE
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name>${NEW_NAME} Configuration</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
    <txt-record>path=/</txt-record>
    <txt-record>product=NDI Bridge</txt-record>
    <txt-record>name=${NEW_NAME}</txt-record>
  </service>
</service-group>
EOFHTTPSERVICE

# Apply hostname immediately
hostname "$FULL_HOSTNAME"

# Restart NDI Bridge service to apply new name
log "Restarting NDI Bridge service..."
systemctl restart ndi-bridge

# Restart Avahi to advertise new name and services
if systemctl is-active --quiet avahi-daemon; then
    log "Restarting Avahi daemon..."
    systemctl restart avahi-daemon
fi

# Show success
log "Device name successfully changed!"
echo ""
echo -e "${CYAN}Summary:${NC}"
echo "  Hostname:      $FULL_HOSTNAME"
echo "  Short alias:   ${NEW_NAME}.local"
echo "  NDI Name:      $NEW_NAME"
echo ""
echo -e "${CYAN}Network Access:${NC}"
echo "  - ping ${FULL_HOSTNAME}.local"
echo "  - ping ${NEW_NAME}.local"
echo ""
echo -e "${CYAN}Web Interface (future):${NC}"
echo "  - http://${FULL_HOSTNAME}.local"
echo "  - http://${NEW_NAME}.local"
echo ""
echo "The device will now appear as '$NEW_NAME' in NDI sources."
echo "You may need to refresh your NDI receiver application."
EOFSETNAME
chmod +x /usr/local/bin/ndi-bridge-set-name

# ndi-bridge-logs
cat > /usr/local/bin/ndi-bridge-logs << 'EOFLOGS'
#!/bin/bash
# View NDI Bridge logs

echo "NDI Bridge Logs (press 'q' to quit):"
echo "===================================="
journalctl -u ndi-bridge --no-pager | less
EOFLOGS
chmod +x /usr/local/bin/ndi-bridge-logs

# ndi-bridge-update
cat > /usr/local/bin/ndi-bridge-update << 'EOFUPDATE'
#!/bin/bash
# Update NDI Bridge binary from USB or network

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    error "This script must be run as root"
fi

echo "NDI Bridge Update Tool"
echo "====================="
echo ""
echo "Update source:"
echo "1) From mounted USB device"
echo "2) From network URL"
echo ""
read -p "Select option (1-2): " option

case $option in
    1)
        # Update from USB
        echo ""
        echo "Available USB devices:"
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk|part"
        echo ""
        read -p "Enter path to ndi-bridge binary (e.g., /mnt/usb/ndi-bridge): " BINARY_PATH
        
        if [ ! -f "$BINARY_PATH" ]; then
            error "Binary not found at $BINARY_PATH"
        fi
        ;;
    2)
        # Update from network
        echo ""
        read -p "Enter URL to ndi-bridge binary: " BINARY_URL
        
        log "Downloading binary..."
        BINARY_PATH="/tmp/ndi-bridge-new"
        if ! wget -O "$BINARY_PATH" "$BINARY_URL"; then
            error "Failed to download binary"
        fi
        ;;
    *)
        error "Invalid option"
        ;;
esac

# Verify it's a valid binary
if ! file "$BINARY_PATH" | grep -q "ELF.*executable"; then
    error "File is not a valid executable binary"
fi

# Check version
log "Checking new binary version..."
NEW_VERSION=$("$BINARY_PATH" --version 2>&1 | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /[0-9]+\.[0-9]+\.[0-9]+/) print $i}' || echo "Unknown")
CURRENT_VERSION=$(/opt/ndi-bridge/ndi-bridge --version 2>&1 | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /[0-9]+\.[0-9]+\.[0-9]+/) print $i}' || echo "Unknown")

echo ""
echo "Current version: $CURRENT_VERSION"
echo "New version:     $NEW_VERSION"
echo ""
read -p "Continue with update? (y/N): " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "Update cancelled"
    exit 0
fi

# Remount root as read-write
mount -o remount,rw / 2>/dev/null || true

# Stop service
log "Stopping NDI Bridge service..."
systemctl stop ndi-bridge

# Backup current binary
log "Backing up current binary..."
cp /opt/ndi-bridge/ndi-bridge /opt/ndi-bridge/ndi-bridge.backup

# Copy new binary
log "Installing new binary..."
cp "$BINARY_PATH" /opt/ndi-bridge/ndi-bridge
chmod +x /opt/ndi-bridge/ndi-bridge

# Start service
log "Starting NDI Bridge service..."
systemctl start ndi-bridge

# Check if service started successfully
sleep 2
if systemctl is-active --quiet ndi-bridge; then
    log "Update successful! NDI Bridge is running with version $NEW_VERSION"
else
    warn "Service failed to start, rolling back..."
    cp /opt/ndi-bridge/ndi-bridge.backup /opt/ndi-bridge/ndi-bridge
    systemctl start ndi-bridge
    error "Update failed, rolled back to previous version"
fi

# Cleanup
rm -f "$BINARY_PATH" 2>/dev/null || true
EOFUPDATE
chmod +x /usr/local/bin/ndi-bridge-update

# ndi-bridge-netstat
cat > /usr/local/bin/ndi-bridge-netstat << 'EOFNETSTAT'
#!/bin/bash
# Show network bridge status

echo "Network Bridge Status"
echo "===================="
echo ""

# Bridge status
echo "Bridge Interface (br0):"
ip -s link show br0
echo ""

# Bridge members
echo "Bridge Members:"
bridge link show
echo ""

# IP configuration
echo "IP Configuration:"
ip addr show br0
echo ""

# Routing table
echo "Routing Table:"
ip route
echo ""

# Connection status
echo "Active Connections:"
ss -tuln | grep -E "^(tcp|udp)" | head -20
EOFNETSTAT
chmod +x /usr/local/bin/ndi-bridge-netstat

# ndi-bridge-netmon
cat > /usr/local/bin/ndi-bridge-netmon << 'EOFNETMON'
#!/bin/bash
# Network bandwidth monitor

echo "Network Bandwidth Monitor"
echo "========================"
echo ""

# Check which tool is available
if command -v nload >/dev/null 2>&1; then
    echo "Starting nload (press 'q' to quit)..."
    sleep 1
    nload br0
elif command -v iftop >/dev/null 2>&1; then
    echo "Starting iftop (press 'q' to quit)..."
    echo "Note: Run with sudo if permission denied"
    sleep 1
    iftop -i br0
elif command -v bmon >/dev/null 2>&1; then
    echo "Starting bmon (press 'q' to quit)..."
    sleep 1
    bmon -p br0
else
    echo "No network monitoring tool found."
    echo "Using basic statistics (updates every 2 seconds, Ctrl+C to stop):"
    echo ""
    
    # Basic monitoring loop
    while true; do
        RX1=$(cat /sys/class/net/br0/statistics/rx_bytes)
        TX1=$(cat /sys/class/net/br0/statistics/tx_bytes)
        sleep 2
        RX2=$(cat /sys/class/net/br0/statistics/rx_bytes)
        TX2=$(cat /sys/class/net/br0/statistics/tx_bytes)
        
        RX_RATE=$(( ($RX2 - $RX1) / 2 / 1024 ))
        TX_RATE=$(( ($TX2 - $TX1) / 2 / 1024 ))
        
        printf "\r[br0] RX: %6d KB/s   TX: %6d KB/s   " $RX_RATE $TX_RATE
    done
fi
EOFNETMON
chmod +x /usr/local/bin/ndi-bridge-netmon

# ndi-bridge-help
cat > /usr/local/bin/ndi-bridge-help << 'EOFHELP'
#!/bin/bash
# Show all available NDI Bridge commands

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    NDI Bridge Commands                        ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}System Information:${NC}"
echo -e "  ${YELLOW}ndi-bridge-info${NC}         - Display comprehensive system status"
echo -e "  ${YELLOW}ndi-bridge-logs${NC}         - View NDI Bridge service logs"
echo ""

echo -e "${CYAN}Configuration:${NC}"
echo -e "  ${YELLOW}ndi-bridge-set-name${NC}     - Set device name (hostname & NDI name)"
echo -e "  ${YELLOW}ndi-bridge-update${NC}       - Update NDI Bridge binary"
echo ""

echo -e "${CYAN}Network Monitoring:${NC}"
echo -e "  ${YELLOW}ndi-bridge-netstat${NC}      - Show network bridge status"
echo -e "  ${YELLOW}ndi-bridge-netmon${NC}       - Monitor network bandwidth in real-time"
echo ""

echo -e "${CYAN}Service Control:${NC}"
echo -e "  ${YELLOW}systemctl start ndi-bridge${NC}   - Start NDI Bridge service"
echo -e "  ${YELLOW}systemctl stop ndi-bridge${NC}    - Stop NDI Bridge service"
echo -e "  ${YELLOW}systemctl restart ndi-bridge${NC} - Restart NDI Bridge service"
echo -e "  ${YELLOW}systemctl status ndi-bridge${NC}  - Check service status"
echo ""

echo -e "${CYAN}Console Switching:${NC}"
echo "  • TTY1 (Alt+F1) - Live NDI logs"
echo "  • TTY2 (Alt+F2) - System menu"
echo "  • TTY3-6 (Alt+F3-F6) - Additional terminals"
echo ""

echo -e "${CYAN}System Commands:${NC}"
echo -e "  ${YELLOW}ip addr${NC}                 - Show network interfaces"
echo -e "  ${YELLOW}htop${NC}                    - System resource monitor"
echo -e "  ${YELLOW}v4l2-ctl --list-devices${NC} - List video devices"
echo ""
EOFHELP
chmod +x /usr/local/bin/ndi-bridge-help

EOFHELPERS
}

export -f create_all_helper_scripts
