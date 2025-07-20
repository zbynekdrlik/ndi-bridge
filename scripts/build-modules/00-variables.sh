#!/bin/bash
# Build system variables and configuration
# This module defines all global variables used throughout the build process

# Build Script Version
BUILD_SCRIPT_VERSION="1.2.1"
BUILD_SCRIPT_DATE="2025-07-20"

# Configuration
USB_DEVICE="${1:-/dev/sdb}"
NDI_BINARY_PATH="$(dirname "$0")/../build/bin/ndi-bridge"
NDI_SDK_PATH="$(dirname "$0")/../../NDI SDK for Linux"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ubuntu version and architecture
UBUNTU_VERSION="noble"  # 24.04 LTS
UBUNTU_ARCH="amd64"

# Default credentials
ROOT_PASSWORD="NewLevel123!"

# Network configuration
DEFAULT_HOSTNAME="ndi-bridge"

# Export all variables
export BUILD_SCRIPT_VERSION BUILD_SCRIPT_DATE
export USB_DEVICE NDI_BINARY_PATH NDI_SDK_PATH
export RED GREEN YELLOW NC
export UBUNTU_VERSION UBUNTU_ARCH
export ROOT_PASSWORD DEFAULT_HOSTNAME