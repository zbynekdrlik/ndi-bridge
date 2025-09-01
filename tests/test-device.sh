#!/bin/bash
# Test Device Helper - Handles SSH key changes automatically for reflashed devices
# Usage: ./test-device.sh [IP_ADDRESS]
# If no IP provided, reads from test_config.yaml

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get IP from argument or config file
if [ -n "$1" ]; then
    IP="$1"
    echo -e "${GREEN}Using IP from command line: $IP${NC}"
elif [ -f "$SCRIPT_DIR/test_config.yaml" ]; then
    IP=$(grep "^host:" "$SCRIPT_DIR/test_config.yaml" | awk '{print $2}')
    if [ -n "$IP" ]; then
        echo -e "${GREEN}Using IP from test_config.yaml: $IP${NC}"
    fi
fi

# Fallback to environment or default
if [ -z "$IP" ]; then
    IP="${NDI_TEST_HOST:-10.77.9.143}"
    echo -e "${YELLOW}Using fallback IP: $IP${NC}"
fi

# Get SSH key from config or use default
SSH_KEY="$HOME/.ssh/ndi_test_key"
if [ -f "$SCRIPT_DIR/test_config.yaml" ]; then
    CONFIG_KEY=$(grep "^ssh_key:" "$SCRIPT_DIR/test_config.yaml" | awk '{print $2}')
    if [ -n "$CONFIG_KEY" ]; then
        # Expand tilde to home directory
        SSH_KEY="${CONFIG_KEY/#\~/$HOME}"
    fi
fi

echo -e "${YELLOW}Testing device at $IP${NC}"

# Remove old SSH host key
echo "Removing old SSH host key..."
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" 2>/dev/null || true

# Add new SSH host key
echo "Scanning for new SSH host key..."
ssh-keyscan -H "$IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null || {
    echo -e "${RED}Failed to scan SSH host key. Is the device online?${NC}"
    exit 1
}

# Run pytest with appropriate authentication
if [ -f "$SSH_KEY" ]; then
    echo -e "${GREEN}Running tests with SSH key: $SSH_KEY${NC}"
    python3 -m pytest "$SCRIPT_DIR" --host "$IP" --ssh-key "$SSH_KEY" -q --tb=no "$@"
else
    echo -e "${YELLOW}SSH key not found, using password authentication${NC}"
    python3 -m pytest "$SCRIPT_DIR" --host "$IP" --ssh-pass newlevel -q --tb=no "$@"
fi

echo -e "${GREEN}Testing complete!${NC}"