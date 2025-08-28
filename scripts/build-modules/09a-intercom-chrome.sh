#!/bin/bash
# Install VDO.Ninja Intercom with Chrome and Dependencies

source "$(dirname "$0")/00-variables.sh"
source "$(dirname "$0")/../build-lib/logging.sh"

log_info "Installing VDO.Ninja Intercom with Chrome..."

# Install Xvfb for virtual display
log_info "Installing Xvfb virtual display server..."
chroot /mnt/usb apt-get install -y -qq xvfb xauth xfonts-100dpi xfonts-75dpi xfonts-cyrillic xfonts-scalable xfonts-base 2>&1 | head -20

# Add Google Chrome repository and install
log_info "Installing Google Chrome..."
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | chroot /mnt/usb apt-key add - 2>/dev/null
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /mnt/usb/etc/apt/sources.list.d/google-chrome.list
chroot /mnt/usb apt-get update -qq 2>&1 | head -5
chroot /mnt/usb apt-get install -y -qq google-chrome-stable 2>&1 | head -20

# Install ALSA utilities for audio
log_info "Installing ALSA utilities..."
chroot /mnt/usb apt-get install -y -qq alsa-utils alsa-base 2>&1 | head -10

# Install PipeWire audio system with PulseAudio utilities
log_info "Installing PipeWire audio system..."
chroot /mnt/usb apt-get install -y -qq pipewire pipewire-alsa pipewire-pulse wireplumber pulseaudio-utils 2>&1 | head -20

# Install PipeWire as system-wide services
log_info "Configuring PipeWire as system services..."
cp "$SCRIPT_DIR/helper-scripts/pipewire-system.service" /mnt/usb/etc/systemd/system/
cp "$SCRIPT_DIR/helper-scripts/wireplumber-system.service" /mnt/usb/etc/systemd/system/
cp "$SCRIPT_DIR/helper-scripts/pipewire-pulse-system.service" /mnt/usb/etc/systemd/system/
chmod 644 /mnt/usb/etc/systemd/system/pipewire-*.service
chmod 644 /mnt/usb/etc/systemd/system/wireplumber-*.service

# Enable PipeWire services
chroot /mnt/usb systemctl enable pipewire-system.service 2>&1 | head -5
chroot /mnt/usb systemctl enable wireplumber-system.service 2>&1 | head -5  
chroot /mnt/usb systemctl enable pipewire-pulse-system.service 2>&1 | head -5

# Install x11vnc for remote monitoring
log_info "Installing x11vnc for remote monitoring..."
chroot /mnt/usb apt-get install -y -qq x11vnc 2>&1 | head -10

# Copy and install the VDO.Ninja service
log_info "Configuring VDO.Ninja intercom service..."
cp "$SCRIPT_DIR/helper-scripts/vdo-ninja-intercom.service" /mnt/usb/etc/systemd/system/
chmod 644 /mnt/usb/etc/systemd/system/vdo-ninja-intercom.service

# Enable the service
chroot /mnt/usb systemctl enable vdo-ninja-intercom.service 2>&1 | head -5

log_success "VDO.Ninja Intercom installed and enabled"