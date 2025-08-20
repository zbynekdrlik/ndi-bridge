#!/bin/bash
# NDI Display service configuration module

configure_ndi_display_service() {
    log "Configuring NDI Display service..."
    
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

# Default display configuration
cat > /etc/ndi-bridge/display-config.json << 'EOFCONFIG'
{
  "auto_map": true,
  "default_mappings": [],
  "display_settings": {
    "vsync": true,
    "double_buffer": true
  }
}
EOFCONFIG

# NDI Display runner script
cat > /opt/ndi-bridge/run-display.sh << 'EOFRUN'
#!/bin/bash

# Create log directory if it doesn't exist (tmpfs)
mkdir -p /var/log/ndi-bridge 2>/dev/null || true

# Wait for network
while ! ping -c 1 -W 1 8.8.8.8 &> /dev/null; do
    echo "Waiting for network..."
    sleep 2
done

# Wait for display devices
while [ ! -e /dev/dri/card0 ]; do
    echo "Waiting for display devices..."
    sleep 2
done

# Check time synchronization
check_time_sync() {
    if command -v check_clocks &> /dev/null; then
        if check_clocks &> /dev/null; then
            echo "Time synchronization verified via PTP"
            return 0
        fi
    fi
    
    if command -v chronyc &> /dev/null; then
        if chronyc tracking | grep -q "System time.*within.*offset"; then
            echo "Time synchronization verified via NTP"
            return 0
        fi
    fi
    
    echo "Warning: Could not verify time synchronization status"
    return 0
}

check_time_sync

# Main loop with restart
while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting NDI Display Service"
    if [ -w /var/log/ndi-bridge ]; then
        LD_LIBRARY_PATH=/usr/local/lib /opt/ndi-bridge/ndi-display auto 2>&1 | tee -a /var/log/ndi-bridge/ndi-display.log
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDI Display exited, restarting in 5 seconds..." | tee -a /var/log/ndi-bridge/ndi-display.log
    else
        LD_LIBRARY_PATH=/usr/local/lib /opt/ndi-bridge/ndi-display auto 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDI Display exited, restarting in 5 seconds..."
    fi
    sleep 5
done
EOFRUN
chmod +x /opt/ndi-bridge/run-display.sh

# Systemd service for NDI Display
cat > /etc/systemd/system/ndi-display.service << EOFSERVICE
[Unit]
Description=NDI Display Service
After=network-online.target ndi-bridge.service
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=/opt/ndi-bridge/run-display.sh
StandardOutput=journal
StandardError=journal

# Display permissions
SupplementaryGroups=video render
DeviceAllow=/dev/dri/card* rw
DeviceAllow=/dev/fb* rw

# Real-time priority for video
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=80
LimitRTPRIO=95
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Enable the service
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable ndi-display
fi

# Install helper scripts
mkdir -p /usr/local/bin

# ndi-display-status
cat > /usr/local/bin/ndi-display-status << 'EOFSTATUS'
#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================"
echo "    NDI Display Status"
echo "================================"
echo

if systemctl is-active --quiet ndi-display; then
    echo -e "${GREEN}● ndi-display.service is running${NC}"
    echo
    echo "Current Stream Mappings:"
    echo "------------------------"
    /opt/ndi-bridge/ndi-display status 2>/dev/null || echo "No active mappings"
    echo
    echo "Available Displays:"
    echo "------------------"
    /opt/ndi-bridge/ndi-display displays
    echo
    echo "Recent Activity:"
    echo "---------------"
    journalctl -u ndi-display -n 10 --no-pager
else
    echo -e "${RED}● ndi-display.service is not running${NC}"
    echo
    echo "Start the service with: sudo systemctl start ndi-display"
fi
EOFSTATUS
chmod +x /usr/local/bin/ndi-display-status

# ndi-display-list
cat > /usr/local/bin/ndi-display-list << 'EOFLIST'
#!/bin/bash
set -e
echo "Searching for NDI streams on the network..."
echo "==========================================="
echo
/opt/ndi-bridge/ndi-display list
echo
echo "To display a stream, use:"
echo "  ndi-display-show \"<stream_name>\" <display_number>"
EOFLIST
chmod +x /usr/local/bin/ndi-display-list

# ndi-display-show
cat > /usr/local/bin/ndi-display-show << 'EOFSHOW'
#!/bin/bash
set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <stream_name> <display_number>"
    echo
    echo "Example:"
    echo "  $0 \"Camera 1\" 0"
    echo
    echo "Available displays:"
    /opt/ndi-bridge/ndi-display displays
    exit 1
fi

STREAM_NAME="$1"
DISPLAY_NUM="$2"

echo "Mapping stream '$STREAM_NAME' to display $DISPLAY_NUM..."

if systemctl is-active --quiet ndi-display; then
    echo "Stopping auto-mapping service..."
    sudo systemctl stop ndi-display
fi

/opt/ndi-bridge/ndi-display show "$STREAM_NAME" "$DISPLAY_NUM" &
DISPLAY_PID=$!

echo $DISPLAY_PID > /var/run/ndi-display-$DISPLAY_NUM.pid
echo "Stream is now displaying on HDMI-$((DISPLAY_NUM + 1))"
echo "To stop: ndi-display-stop $DISPLAY_NUM"
EOFSHOW
chmod +x /usr/local/bin/ndi-display-show

# ndi-display-stop
cat > /usr/local/bin/ndi-display-stop << 'EOFSTOP'
#!/bin/bash
set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <display_number>"
    exit 1
fi

DISPLAY_NUM="$1"
PID_FILE="/var/run/ndi-display-$DISPLAY_NUM.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping display $DISPLAY_NUM (PID: $PID)..."
        kill "$PID"
        rm -f "$PID_FILE"
        echo "Display $DISPLAY_NUM stopped."
    else
        echo "Display $DISPLAY_NUM is not running"
        rm -f "$PID_FILE"
    fi
else
    echo "Display $DISPLAY_NUM is not running"
fi
EOFSTOP
chmod +x /usr/local/bin/ndi-display-stop

# ndi-display-auto
cat > /usr/local/bin/ndi-display-auto << 'EOFAUTO'
#!/bin/bash
set -e

echo "Starting automatic NDI stream mapping..."
echo "========================================"
echo

echo "Stopping existing display mappings..."
for i in 0 1 2; do
    if [ -f "/var/run/ndi-display-$i.pid" ]; then
        ndi-display-stop $i 2>/dev/null || true
    fi
done

echo "Starting auto-mapping service..."
sudo systemctl start ndi-display

echo
echo "Auto-mapping service started."
echo "Check status with: ndi-display-status"
EOFAUTO
chmod +x /usr/local/bin/ndi-display-auto

EOFNDIDISPLAY
}

export -f configure_ndi_display_service