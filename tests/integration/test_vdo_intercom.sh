#!/bin/bash
# Test VDO.Ninja Intercom functionality

set -e

echo "=== VDO.Ninja Intercom Integration Test ==="

# Test configuration
TIMEOUT=30
SERVICE="vdo-ninja-intercom"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to check if a process is running
check_process() {
    local process=$1
    if pgrep -f "$process" > /dev/null; then
        echo -e "${GREEN}✓${NC} $process is running"
        return 0
    else
        echo -e "${RED}✗${NC} $process is NOT running"
        return 1
    fi
}

# Function to check URL parameters
check_url_params() {
    local url=$(ps aux | grep chrome | grep vdo | head -1 | grep -o 'https://vdo.ninja[^ ]*' || echo "")
    
    if [ -z "$url" ]; then
        echo -e "${RED}✗${NC} Chrome not running with VDO.Ninja URL"
        return 1
    fi
    
    echo "URL: $url"
    
    # Check critical parameters
    local failed=0
    
    if echo "$url" | grep -q "&miconly"; then
        echo -e "${GREEN}✓${NC} miconly parameter present (no camera prompt)"
    else
        echo -e "${RED}✗${NC} miconly parameter missing - will show camera prompt!"
        failed=1
    fi
    
    if echo "$url" | grep -q "&autostart"; then
        echo -e "${GREEN}✓${NC} autostart parameter present"
    else
        echo -e "${RED}✗${NC} autostart parameter missing"
        failed=1
    fi
    
    if echo "$url" | grep -q "room="; then
        echo -e "${GREEN}✓${NC} room parameter present"
    else
        echo -e "${RED}✗${NC} room parameter missing"
        failed=1
    fi
    
    if echo "$url" | grep -q "&push="; then
        echo -e "${GREEN}✓${NC} push parameter present"
    else
        echo -e "${RED}✗${NC} push parameter missing"
        failed=1
    fi
    
    # Check for wrong parameters that would cause camera prompt
    if echo "$url" | grep -q "&webcam"; then
        echo -e "${RED}✗${NC} webcam parameter present - will cause camera prompt!"
        failed=1
    fi
    
    if echo "$url" | grep -q "&videodevice="; then
        echo -e "${RED}✗${NC} videodevice parameter present - will cause camera issues!"
        failed=1
    fi
    
    return $failed
}

# Function to check audio setup
check_audio() {
    # Check if PipeWire is running
    if ! check_process "pipewire"; then
        return 1
    fi
    
    # Check if USB Audio is detected
    if pactl list sinks short 2>/dev/null | grep -q "USB.*Audio\|usb"; then
        echo -e "${GREEN}✓${NC} USB Audio detected by PipeWire"
        
        # Check if it's set as default
        local default_sink=$(pactl info 2>/dev/null | grep "Default Sink" | cut -d: -f2 | tr -d ' ')
        if echo "$default_sink" | grep -q -i "usb"; then
            echo -e "${GREEN}✓${NC} USB Audio is default output"
        else
            echo -e "${RED}✗${NC} USB Audio is NOT default output"
            return 1
        fi
    else
        echo -e "${RED}✗${NC} USB Audio NOT detected"
        return 1
    fi
    
    return 0
}

# Main test sequence
echo ""
echo "1. Checking service status..."
if systemctl is-active --quiet $SERVICE; then
    echo -e "${GREEN}✓${NC} Service is active"
else
    echo -e "${RED}✗${NC} Service is not active"
    exit 1
fi

echo ""
echo "2. Checking Chrome process..."
check_process "chrome" || exit 1

echo ""
echo "3. Checking VDO.Ninja URL parameters..."
check_url_params || exit 1

echo ""
echo "4. Checking PipeWire audio..."
check_audio || exit 1

echo ""
echo "5. Checking VNC access..."
if check_process "x11vnc"; then
    if netstat -tuln | grep -q ":5999 "; then
        echo -e "${GREEN}✓${NC} VNC listening on port 5999"
    else
        echo -e "${RED}✗${NC} VNC port 5999 not listening"
        exit 1
    fi
else
    exit 1
fi

echo ""
echo "6. Checking Xvfb display..."
check_process "Xvfb" || exit 1

echo ""
echo "7. Checking welcome screen integration..."
# Test that welcome screen would show intercom status correctly
if command -v ndi-bridge-welcome >/dev/null 2>&1; then
    # The welcome script should detect vdo-ninja-intercom service
    if ndi-bridge-welcome 2>/dev/null | grep -q "INTERCOM STATUS"; then
        echo -e "${GREEN}✓${NC} Welcome screen has intercom section"
    else
        echo -e "${YELLOW}⚠${NC} Welcome screen may not show intercom status"
    fi
else
    echo -e "${YELLOW}⚠${NC} ndi-bridge-welcome not found (OK in test environment)"
fi

echo ""
echo "=== All tests passed! ==="
echo "VDO.Ninja intercom is functioning correctly"
echo "- Audio-only mode (no camera prompt)"
echo "- PipeWire with USB Audio"
echo "- VNC monitoring available"
echo "- Auto-join to room enabled"

exit 0