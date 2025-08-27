#!/bin/bash
# Install dependencies for Chrome-based VDO.Ninja intercom with virtual display
# This uses full Chrome (not headless) with Xvfb to avoid blocking HDMI ports

set -e

echo "=== Installing Chrome VDO.Ninja Intercom Dependencies ==="

# Update package list
echo "Updating package list..."
apt-get update -qq

# Install Xvfb and X11 dependencies for virtual display
echo "Installing Xvfb virtual display server..."
apt-get install -y -qq \
    xvfb \
    x11-xkb-utils \
    xfonts-100dpi \
    xfonts-75dpi \
    xfonts-scalable \
    xfonts-cyrillic \
    xserver-xorg-core

# Install Chrome if not already installed
if ! command -v google-chrome &> /dev/null; then
    echo "Installing Google Chrome..."
    wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
    apt-get update -qq
    apt-get install -y -qq google-chrome-stable
else
    echo "Google Chrome already installed"
fi

# Install ALSA utilities for audio configuration
echo "Installing ALSA utilities..."
apt-get install -y -qq alsa-utils

# Install PipeWire and WirePlumber for audio handling (required)
echo "Installing PipeWire audio system..."
apt-get install -y -qq \
    pipewire \
    pipewire-alsa \
    pipewire-pulse \
    wireplumber \
    pipewire-bin \
    libpipewire-0.3-modules

# Install VNC server for remote monitoring (optional but useful)
echo "Installing x11vnc for remote monitoring..."
apt-get install -y -qq x11vnc

# Clean up to save space
apt-get clean
apt-get autoremove -y

echo "✓ Chrome intercom dependencies installed successfully"
echo ""
echo "Components installed:"
echo "  - Xvfb (virtual display server)"
echo "  - X11 fonts for proper rendering"
echo "  - Google Chrome (full version)"
echo "  - ALSA utilities for audio control"
echo "  - PipeWire audio system with WirePlumber"
echo "  - x11vnc for remote monitoring"