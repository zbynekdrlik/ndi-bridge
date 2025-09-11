#!/bin/bash
# Verification script for PipeWire user mode migration
# This script checks that all components are working correctly after migration

set -e

echo "========================================="
echo "PipeWire User Mode Verification Script"
echo "========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track overall status
ERRORS=0
WARNINGS=0

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

echo "1. Checking user and groups..."
if id -u mediabridge >/dev/null 2>&1; then
    check_pass "mediabridge user exists"
    USER_INFO=$(id mediabridge)
    echo "   $USER_INFO"
    
    if [[ "$USER_INFO" == *"uid=999"* ]]; then
        check_pass "mediabridge has correct UID (999)"
    else
        check_fail "mediabridge has wrong UID (expected 999)"
    fi
    
    if [[ "$USER_INFO" == *"audio"* ]]; then
        check_pass "mediabridge is in audio group"
    else
        check_fail "mediabridge is not in audio group"
    fi
else
    check_fail "mediabridge user does not exist"
fi

echo ""
echo "2. Checking systemd services..."

# Check user@999 service
if systemctl is-active user@999.service >/dev/null 2>&1; then
    check_pass "user@999.service is active"
else
    check_fail "user@999.service is not active"
    systemctl status user@999.service --no-pager | head -10
fi

# Check for circular dependencies
echo ""
echo "3. Checking for circular dependencies..."
AFTER_DEPS=$(systemctl show user@999.service -p After --value)
if [[ "$AFTER_DEPS" == *"multi-user.target"* ]]; then
    check_fail "user@999.service has After=multi-user.target (circular dependency!)"
else
    check_pass "No circular dependency detected in user@999.service"
fi

# Check PipeWire user services
echo ""
echo "4. Checking PipeWire user services..."
for service in pipewire pipewire-pulse wireplumber; do
    if sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user is-active $service >/dev/null 2>&1; then
        check_pass "$service user service is active"
    else
        check_fail "$service user service is not active"
        sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user status $service --no-pager | head -5
    fi
done

# Check loginctl linger
echo ""
echo "5. Checking loginctl linger..."
if [ -f /var/lib/systemd/linger/mediabridge ]; then
    check_pass "loginctl linger enabled for mediabridge"
else
    check_fail "loginctl linger not enabled for mediabridge"
fi

# Check realtime limits
echo ""
echo "6. Checking realtime scheduling limits..."
if [ -f /etc/security/limits.d/99-mediabridge.conf ]; then
    check_pass "Realtime limits configuration exists"
    if grep -q "mediabridge.*rtprio.*95" /etc/security/limits.d/99-mediabridge.conf; then
        check_pass "mediabridge has rtprio 95"
    else
        check_fail "mediabridge missing rtprio 95"
    fi
else
    check_fail "Realtime limits configuration missing"
fi

# Check directories
echo ""
echo "7. Checking required directories..."
DIRS=(
    "/run/pipewire"
    "/run/user/999"
    "/var/lib/mediabridge"
    "/var/lib/mediabridge/.config"
    "/var/lib/mediabridge/.config/systemd/user"
    "/var/lib/mediabridge/.config/wireplumber"
)

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        check_pass "$dir exists"
        OWNER=$(stat -c "%U:%G" "$dir")
        if [[ "$OWNER" == "mediabridge:audio" ]] || [[ "$OWNER" == "mediabridge:mediabridge" ]]; then
            check_pass "  Ownership: $OWNER"
        else
            check_warn "  Ownership: $OWNER (expected mediabridge:audio)"
        fi
    else
        check_fail "$dir does not exist"
    fi
done

# Check PipeWire sockets
echo ""
echo "8. Checking PipeWire sockets..."
if [ -S /run/user/999/pipewire-0 ]; then
    check_pass "/run/user/999/pipewire-0 socket exists"
else
    check_fail "/run/user/999/pipewire-0 socket missing"
fi

if [ -S /run/pipewire/pipewire-0 ]; then
    check_pass "/run/pipewire/pipewire-0 bind mount exists"
else
    check_warn "/run/pipewire/pipewire-0 bind mount missing (will be created on service start)"
fi

if [ -S /run/user/999/pulse/native ]; then
    check_pass "/run/user/999/pulse/native socket exists"
else
    check_fail "/run/user/999/pulse/native socket missing"
fi

# Check audio functionality
echo ""
echo "9. Testing audio functionality..."
if sudo -u mediabridge XDG_RUNTIME_DIR=/run/pipewire PULSE_RUNTIME_PATH=/run/pipewire/pulse pactl info >/dev/null 2>&1; then
    check_pass "PulseAudio protocol is accessible"
    SERVER_NAME=$(sudo -u mediabridge XDG_RUNTIME_DIR=/run/pipewire PULSE_RUNTIME_PATH=/run/pipewire/pulse pactl info | grep "Server Name" | cut -d: -f2 | xargs)
    echo "   Server: $SERVER_NAME"
else
    check_fail "Cannot connect to PulseAudio protocol"
fi

# Check virtual devices
echo ""
echo "10. Checking virtual audio devices..."
VIRTUAL_DEVICES=$(sudo -u mediabridge XDG_RUNTIME_DIR=/run/pipewire PULSE_RUNTIME_PATH=/run/pipewire/pulse pactl list short sinks 2>/dev/null | grep -E "intercom-speaker|intercom-microphone" || true)
if [ -n "$VIRTUAL_DEVICES" ]; then
    check_pass "Virtual audio devices found:"
    echo "$VIRTUAL_DEVICES" | while read line; do
        echo "   $line"
    done
else
    check_warn "Virtual audio devices not found (will be created by audio manager)"
fi

# Check Chrome profile
echo ""
echo "11. Checking Chrome profile location..."
if [ -d /var/lib/mediabridge/chrome-profile ]; then
    check_pass "Chrome profile directory exists"
    OWNER=$(stat -c "%U:%G" /var/lib/mediabridge/chrome-profile)
    if [[ "$OWNER" == "mediabridge:audio" ]]; then
        check_pass "  Ownership: $OWNER"
    else
        check_fail "  Ownership: $OWNER (expected mediabridge:audio)"
    fi
else
    check_warn "Chrome profile directory not found (will be created on first run)"
fi

# Check intercom service
echo ""
echo "12. Checking media-bridge-intercom service..."
if systemctl is-enabled media-bridge-intercom >/dev/null 2>&1; then
    check_pass "media-bridge-intercom is enabled"
else
    check_fail "media-bridge-intercom is not enabled"
fi

if systemctl is-active media-bridge-intercom >/dev/null 2>&1; then
    check_pass "media-bridge-intercom is active"
else
    check_warn "media-bridge-intercom is not active (may not have started yet)"
fi

# Check environment variables
echo ""
echo "13. Checking environment variables..."
if grep -q "XDG_RUNTIME_DIR=/run/pipewire" /etc/environment; then
    check_pass "XDG_RUNTIME_DIR set to /run/pipewire in /etc/environment"
else
    check_fail "XDG_RUNTIME_DIR not updated in /etc/environment"
fi

# Final summary
echo ""
echo "========================================="
echo "Verification Summary"
echo "========================================="
if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}All checks passed successfully!${NC}"
        echo "PipeWire user mode is fully operational."
    else
        echo -e "${GREEN}Core functionality working with $WARNINGS warnings.${NC}"
        echo "System should be operational but review warnings above."
    fi
    exit 0
else
    echo -e "${RED}Found $ERRORS errors and $WARNINGS warnings.${NC}"
    echo "PipeWire user mode needs attention. Review errors above."
    exit 1
fi