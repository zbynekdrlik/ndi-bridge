#!/bin/bash
# Build system variables and configuration
# This module defines all global variables used throughout the build process

# Build Script Version - Auto-incremented with each build
BUILD_SCRIPT_VERSION="2.2.1"
BUILD_SCRIPT_DATE="2025-09-03"

# Build timestamp - Generated at build time (local timezone)
BUILD_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

# Git commit hash - Get current commit for version tracking
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

# Configuration
USB_DEVICE="${1:-/dev/sdb}"
NDI_BINARY_PATH="$(dirname "$0")/../build/bin/ndi-capture"
NDI_DISPLAY_BINARY_PATH="$(dirname "$0")/../build/bin/ndi-display"
NDI_SDK_PATH="$(dirname "$0")/../NDI SDK for Linux"

# Mount point - use local directory in repository to avoid conflicts
# This allows multiple builds to run concurrently in different folders
MOUNT_POINT="$(dirname "$0")/../build-mount"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ubuntu version and architecture
UBUNTU_VERSION="noble"  # 24.04 LTS
UBUNTU_ARCH="amd64"

# Default credentials
ROOT_PASSWORD="newlevel"

# Network configuration
DEFAULT_HOSTNAME="media-bridge"

# Export all variables
export BUILD_SCRIPT_VERSION BUILD_SCRIPT_DATE BUILD_TIMESTAMP GIT_COMMIT
export USB_DEVICE NDI_BINARY_PATH NDI_DISPLAY_BINARY_PATH NDI_SDK_PATH
export MOUNT_POINT
export RED GREEN YELLOW NC
export UBUNTU_VERSION UBUNTU_ARCH
export ROOT_PASSWORD DEFAULT_HOSTNAME
