#!/bin/bash
# Media Bridge Test Device Manager
# 
# SINGLE ENTRY POINT for all Media Bridge testing
# Handles SSH setup, authentication, and test execution
#
# Usage:
#   ./test-device.sh IP_ADDRESS [options...]
#   ./test-device.sh IP_ADDRESS                    # Run ALL 433 tests
#   ./test-device.sh IP_ADDRESS tests/component/   # Run component tests only
#   ./test-device.sh IP_ADDRESS -m critical       # Run critical tests only
#   ./test-device.sh IP_ADDRESS --help             # Show pytest help
#
# Examples:
#   ./test-device.sh 10.77.8.124                           # Complete test suite
#   ./test-device.sh 10.77.8.124 tests/component/audio/   # Audio tests only
#   ./test-device.sh 10.77.8.124 -v                       # Verbose output
#   ./test-device.sh 10.77.8.124 --collect-only           # Quick SSH test
#   ./test-device.sh 10.77.8.124 -m "not slow"           # Skip slow tests

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEY="$HOME/.ssh/ndi_test_key"

# Show usage information
show_usage() {
    echo -e "${BOLD}Media Bridge Test Device Manager${NC}"
    echo
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 IP_ADDRESS [pytest-options...]"
    echo
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 10.77.8.124                           # Run ALL 433 tests (recommended)"
    echo "  $0 10.77.8.124 tests/component/audio/   # Run audio tests only"
    echo "  $0 10.77.8.124 tests/component/capture/ # Run capture tests only"  
    echo "  $0 10.77.8.124 -m critical              # Run critical tests only"
    echo "  $0 10.77.8.124 -v                       # Verbose output"
    echo "  $0 10.77.8.124 --collect-only           # Quick SSH verification"
    echo "  $0 10.77.8.124 -m \"not slow\"           # Skip slow tests"
    echo "  $0 10.77.8.124 --html=report.html       # Generate HTML report"
    echo
    echo -e "${YELLOW}Test Categories:${NC}"
    echo "  tests/component/    - Atomic component tests (312 tests)"
    echo "  tests/integration/  - Functional integration tests (89 tests)"
    echo "  tests/system/       - System-level tests (32 tests)"
    echo
    echo -e "${YELLOW}Test Markers:${NC}"
    echo "  -m critical         - Must-pass tests only (~150 tests)"
    echo "  -m \"not slow\"       - Exclude tests >5 seconds (~350 tests)"
    echo "  -m requires_hardware - Hardware-dependent tests only"
    echo "  -m audio            - Audio system tests"
    echo "  -m network          - Network functionality tests"
    echo
    echo -e "${YELLOW}IP Address is REQUIRED as first parameter.${NC}"
    echo
}

# Validate IP address format
is_valid_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Check for help request or missing IP
if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
fi

# Validate IP address
IP="$1"
if ! is_valid_ip "$IP"; then
    echo -e "${RED}Error: Invalid or missing IP address${NC}"
    echo -e "${YELLOW}First parameter must be a valid IP address (e.g., 10.77.8.124)${NC}"
    echo
    show_usage
    exit 1
fi

shift # Remove IP from arguments

echo -e "${BOLD}Media Bridge Test Suite${NC}"
echo -e "${BLUE}Target Device: $IP${NC}"
echo -e "${BLUE}Test Directory: $SCRIPT_DIR${NC}"
echo

# Check if device is reachable
echo -e "${YELLOW}Checking device connectivity...${NC}"
if ! ping -c 1 -W 3 "$IP" >/dev/null 2>&1; then
    echo -e "${RED}Warning: Device $IP is not responding to ping${NC}"
    echo -e "${YELLOW}Continuing anyway - device might have ICMP disabled${NC}"
fi

# SSH Host Key Management
echo -e "${YELLOW}Setting up SSH host keys...${NC}"
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$IP" 2>/dev/null || true

if ssh-keyscan -H "$IP" >> "$HOME/.ssh/known_hosts" 2>/dev/null; then
    echo -e "${GREEN}✓ SSH host key obtained${NC}"
else
    echo -e "${RED}✗ Failed to scan SSH host key${NC}"
    echo -e "${RED}Device may be offline or SSH service not running${NC}"
    exit 1
fi

# SSH Key Authentication Setup
echo -e "${YELLOW}Setting up SSH authentication...${NC}"
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${YELLOW}Creating SSH key at $SSH_KEY...${NC}"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q
    echo -e "${GREEN}✓ SSH key created${NC}"
else
    echo -e "${GREEN}✓ Using existing SSH key: $SSH_KEY${NC}"
fi

# Copy SSH key to device
echo -e "${YELLOW}Installing SSH key on device...${NC}"
if sshpass -p newlevel ssh-copy-id -i "${SSH_KEY}.pub" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@$IP" 2>/dev/null; then
    echo -e "${GREEN}✓ SSH key authentication configured${NC}"
    AUTH_METHOD="key"
else
    echo -e "${YELLOW}⚠ SSH key installation failed, will use password authentication${NC}"
    AUTH_METHOD="password"
fi

# Test SSH connection
echo -e "${YELLOW}Testing SSH connection...${NC}"
if [ "$AUTH_METHOD" = "key" ]; then
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o PasswordAuthentication=no "root@$IP" "echo 'SSH key auth working'" 2>/dev/null; then
        echo -e "${GREEN}✓ SSH key authentication verified${NC}"
    else
        echo -e "${YELLOW}⚠ SSH key auth failed, falling back to password${NC}"
        AUTH_METHOD="password"
    fi
fi

if [ "$AUTH_METHOD" = "password" ]; then
    if sshpass -p newlevel ssh -o ConnectTimeout=5 "root@$IP" "echo 'SSH password auth working'" 2>/dev/null; then
        echo -e "${GREEN}✓ SSH password authentication verified${NC}"
    else
        echo -e "${RED}✗ All SSH authentication methods failed${NC}"
        exit 1
    fi
fi

# Determine test execution parameters
echo
echo -e "${BOLD}Test Execution Configuration${NC}"

# Count total tests
TOTAL_TESTS=$(python3 -m pytest "$SCRIPT_DIR" --collect-only -q 2>/dev/null | grep -c "test" || echo "unknown")
echo -e "${BLUE}Total tests in suite: $TOTAL_TESTS${NC}"

# Show what will be executed
if [ $# -eq 0 ]; then
    echo -e "${BLUE}Executing: ALL tests (complete suite)${NC}"
    echo -e "${BLUE}Expected runtime: 5-10 minutes${NC}"
    TEST_ARGS=("$SCRIPT_DIR" "--maxfail=0")
else
    echo -e "${BLUE}Executing: Custom test selection${NC}"
    echo -e "${BLUE}Arguments: $*${NC}"
    TEST_ARGS=("$@")
fi

echo -e "${BLUE}Authentication: $AUTH_METHOD${NC}"
echo -e "${BLUE}Auto-retry: Enabled (3 attempts for network issues)${NC}"
echo

# Execute tests
echo -e "${BOLD}Running Tests${NC}"
echo "========================================="

# Build pytest command
PYTEST_CMD=(
    "python3" "-m" "pytest"
    "--host" "$IP"
    "-q" "--tb=short"
)

# Add authentication
if [ "$AUTH_METHOD" = "key" ]; then
    PYTEST_CMD+=("--ssh-key" "$SSH_KEY")
else
    PYTEST_CMD+=("--ssh-pass" "newlevel")
fi

# Add retry configuration
PYTEST_CMD+=(
    "--reruns" "3"
    "--reruns-delay" "5"
    "--only-rerun" "timeout|TimeoutError|ConnectionError|EOFError|Connection reset|Connection refused|No route to host"
)

# Add test arguments
PYTEST_CMD+=("${TEST_ARGS[@]}")

# Execute the test command
echo -e "${YELLOW}Command: ${PYTEST_CMD[*]}${NC}"
echo

if "${PYTEST_CMD[@]}"; then
    echo
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${BOLD}${GREEN}✓ Test execution completed successfully${NC}"
    echo -e "${GREEN}=========================================${NC}"
    exit 0
else
    echo
    echo -e "${RED}=========================================${NC}"
    echo -e "${BOLD}${RED}✗ Test execution completed with failures${NC}"
    echo -e "${RED}=========================================${NC}"
    echo
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "1. Check device status: ssh root@$IP 'systemctl status'"
    echo "2. Check device logs: ssh root@$IP 'journalctl -f'"
    echo "3. Run with verbose output: $0 $IP -v"
    echo "4. Run single test: $0 $IP tests/component/core/test_version_info.py"
    echo
    echo -e "${YELLOW}See docs/TESTING.md for complete troubleshooting guide${NC}"
    exit 1
fi