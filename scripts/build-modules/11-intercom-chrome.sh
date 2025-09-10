#!/bin/bash
# Install Media Bridge Intercom with Chrome and Dependencies
# This module adds Chrome and PipeWire installation to the chroot configuration

# Function to configure Chrome intercom - gets added to chroot script
configure_chrome_intercom() {
    cat >> /mnt/usb/tmp/configure-system.sh << 'CHROME_EOF'

echo "Installing Media Bridge Intercom with Chrome..."

# Create mediabridge user for all Media Bridge services
echo "Creating mediabridge user for unified services..."
if ! id -u mediabridge >/dev/null 2>&1; then
    # Create pipewire group if it doesn't exist
    groupadd --system pipewire 2>/dev/null || true
    
    useradd \
        --system \
        --uid 999 \
        --create-home \
        --home-dir /var/lib/mediabridge \
        --shell /bin/bash \
        --comment "Media Bridge System User" \
        --groups audio,video,pipewire \
        mediabridge
    echo "Mediabridge user created"
else
    echo "Mediabridge user already exists"
fi

# Setup mediabridge user directories
mkdir -p /var/lib/mediabridge/.chrome-profile/Default
mkdir -p /var/lib/mediabridge/tmp
mkdir -p /var/lib/mediabridge/.config/pipewire
mkdir -p /var/lib/mediabridge/.config/wireplumber
mkdir -p /var/lib/mediabridge/.local/share
mkdir -p /var/lib/mediabridge/.local/state
mkdir -p /var/lib/mediabridge/.cache
chown -R mediabridge:mediabridge /var/lib/mediabridge

# Enable lingering for mediabridge user
loginctl enable-linger mediabridge 2>/dev/null || true

# Configure realtime capabilities
cat > /etc/security/limits.d/mediabridge.conf << 'LIMITS'
# Realtime capabilities for mediabridge user
@pipewire   - rtprio  95
@pipewire   - nice    -19
@pipewire   - memlock unlimited

mediabridge   - rtprio  95
mediabridge   - nice    -19
mediabridge   - memlock unlimited
LIMITS

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

# Check if PipeWire 1.4.7 was already installed by module 08
if [ -f /tmp/pipewire-1.4.7-installed ]; then
    echo "PipeWire 1.4.7 already installed by module 08"
else
    # Fallback: Install standard PipeWire if module 08 didn't run
    echo "Installing PipeWire audio system (fallback)..."
    apt-get install -y -qq pipewire pipewire-alsa pipewire-pulse wireplumber pulseaudio-utils 2>&1 | head -20
fi

# Install ALSA utilities for testing
echo "Installing ALSA utilities..."
apt-get install -y -qq alsa-utils 2>&1 | head -10

# Install Python3 for API server
echo "Installing Python3 for API server..."
apt-get install -y -qq python3 python3-minimal 2>&1 | head -10

# Enable Media Bridge intercom services
echo "Enabling Media Bridge intercom services..."
systemctl enable media-bridge-intercom.service 2>/dev/null || true

# Enable system-wide PipeWire services
echo "Enabling system-wide PipeWire services..."
systemctl enable pipewire-system.socket 2>/dev/null || true
systemctl enable pipewire-system.service 2>/dev/null || true
systemctl enable pipewire-pulse-system.service 2>/dev/null || true
systemctl enable wireplumber-system.service 2>/dev/null || true

# Enable audio manager service if it exists
if [ -f /etc/systemd/system/media-bridge-audio-manager.service ]; then
    systemctl enable media-bridge-audio-manager.service 2>/dev/null || true
    echo "Audio manager service enabled"
fi

# Enable permission manager service for strict audio isolation
if [ -f /etc/systemd/system/media-bridge-permission-manager.service ]; then
    systemctl enable media-bridge-permission-manager.service 2>/dev/null || true
    echo "Permission manager service enabled for audio isolation"
fi

# Setup Chrome profile with VDO.Ninja permissions for mediabridge user
echo "Setting up Chrome permissions for mediabridge user..."
cat > /var/lib/mediabridge/.chrome-profile/Default/Preferences << 'PREFS'
{
  "profile": {
    "content_settings": {
      "exceptions": {
        "media_stream_mic": {
          "https://vdo.ninja:443,*": {
            "last_modified": "13400766142668061",
            "setting": 1
          }
        },
        "media_stream_camera": {
          "https://vdo.ninja:443,*": {
            "last_modified": "13400766150219890",
            "setting": 1
          }
        }
      }
    }
  },
  "browser": {
    "check_default_browser": false
  }
}
PREFS
chown -R mediabridge:mediabridge /var/lib/mediabridge/.chrome-profile

echo "Chrome and Media Bridge intercom installation complete"

CHROME_EOF
}

# The function is defined above and will be called by assemble_configuration()
# in the main script when it's time to add to the chroot configuration