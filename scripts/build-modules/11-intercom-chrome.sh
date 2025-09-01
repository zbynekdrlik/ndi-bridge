#!/bin/bash
# Install NDI Bridge Intercom with Chrome and Dependencies
# This module adds Chrome and PipeWire installation to the chroot configuration

# Function to configure Chrome intercom - gets added to chroot script
configure_chrome_intercom() {
    cat >> /mnt/usb/tmp/configure-system.sh << 'CHROME_EOF'

echo "Installing NDI Bridge Intercom with Chrome..."

# Install Xvfb for virtual display
echo "Installing Xvfb virtual display server..."
apt-get install -y -qq xvfb xauth xfonts-100dpi xfonts-75dpi xfonts-cyrillic xfonts-scalable xfonts-base 2>&1 | head -20

# Install x11vnc for remote access
echo "Installing x11vnc..."
apt-get install -y -qq x11vnc 2>&1 | head -20

# Install Google Chrome
echo "Installing Google Chrome..."
# Install gpg first if not present
apt-get install -y -qq gnupg 2>&1 | head -10
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/google-chrome.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
apt-get update -qq 2>&1 | head -10
apt-get install -y -qq google-chrome-stable 2>&1 | head -30

# Install PipeWire audio system with PulseAudio utilities
echo "Installing PipeWire audio system..."
apt-get install -y -qq pipewire pipewire-alsa pipewire-pulse wireplumber pulseaudio-utils 2>&1 | head -20

# Install ALSA utilities for testing
echo "Installing ALSA utilities..."
apt-get install -y -qq alsa-utils 2>&1 | head -10

# Install Python3 for API server
echo "Installing Python3 for API server..."
apt-get install -y -qq python3 python3-minimal 2>&1 | head -10

# Enable NDI Bridge intercom services
echo "Enabling NDI Bridge intercom services..."
systemctl enable ndi-bridge-intercom.service 2>/dev/null || true

echo "Chrome and NDI Bridge intercom installation complete"

CHROME_EOF
}

# The function is defined above and will be called by assemble_configuration()
# in the main script when it's time to add to the chroot configuration