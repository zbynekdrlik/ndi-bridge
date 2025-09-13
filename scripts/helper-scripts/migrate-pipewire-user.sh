#!/bin/bash
# Migration script for existing Media Bridge deployments
# Migrates PipeWire from root to mediabridge user

set -e

echo "========================================="
echo "Media Bridge PipeWire User Migration"
echo "========================================="
echo ""
echo "This script migrates your PipeWire audio system to run as the mediabridge user via a standard systemd user session."
echo ""
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

# Stop all services
echo "Stopping all Media Bridge services..."
systemctl stop media-bridge-intercom 2>/dev/null || true
systemctl stop ndi-display@0 ndi-display@1 ndi-display@2 2>/dev/null || true
systemctl stop ndi-capture 2>/dev/null || true
systemctl stop pipewire-system 2>/dev/null || true
systemctl stop pipewire-pulse-system 2>/dev/null || true
systemctl stop wireplumber-system 2>/dev/null || true

# Create mediabridge user if it doesn't exist
echo "Ensuring mediabridge user exists..."
groupadd -r pipewire 2>/dev/null || true
groupadd -r render 2>/dev/null || true
groupadd -r input 2>/dev/null || true
if ! id -u mediabridge >/dev/null 2>&1; then
    useradd -m -u 1001 -g audio -G pipewire,video,input,render,sudo -s /bin/bash -c "Media Bridge User" mediabridge || true
else
    usermod -a -G pipewire,video,input,render,audio mediabridge || true
fi

# Enable persistent user session
echo "Enabling persistent user session..."
loginctl enable-linger mediabridge

echo "Creating required directories..."
mkdir -p /home/mediabridge/.config/systemd/user/default.target.wants
mkdir -p /home/mediabridge/.config/wireplumber/wireplumber.conf.d
mkdir -p /var/run/ndi-display /var/run/media-bridge
chown -R mediabridge:audio /home/mediabridge/.config
chown mediabridge:audio /var/run/ndi-display
chown mediabridge:audio /var/run/media-bridge

# Move Chrome profile if it exists
if [ -d /tmp/chrome-vdo-profile ]; then
    echo "Migrating Chrome profile..."
    mv /tmp/chrome-vdo-profile /var/lib/mediabridge/chrome-profile
    chown -R mediabridge:audio /var/lib/mediabridge/chrome-profile
elif [ -d /opt/chrome-vdo-profile ]; then
    echo "Migrating Chrome profile from /opt..."
    mv /opt/chrome-vdo-profile /var/lib/mediabridge/chrome-profile
    chown -R mediabridge:audio /var/lib/mediabridge/chrome-profile
fi

# Create realtime scheduling limits
echo "Setting up realtime scheduling limits..."
cat > /etc/security/limits.d/99-mediabridge.conf << 'EOF'
# Media Bridge realtime audio configuration
@audio   -  rtprio     95
@audio   -  nice      -19
@audio   -  memlock    unlimited

mediabridge   -  rtprio     95
mediabridge   -  nice      -19
mediabridge   -  memlock    unlimited
EOF

# Create tmpfiles.d configuration
echo "Creating tmpfiles.d configuration..."
cat > /etc/tmpfiles.d/mediabridge.conf << 'EOF'
# Runtime directories for Media Bridge
d /var/run/ndi-display 0755 mediabridge audio -
d /var/run/media-bridge 0755 mediabridge audio -
EOF

# Apply tmpfiles configuration
systemd-tmpfiles --create /etc/tmpfiles.d/mediabridge.conf

echo "Enabling PipeWire user services for mediabridge..."
mkdir -p /home/mediabridge/.config/systemd/user/default.target.wants
for u in pipewire.service pipewire-pulse.service wireplumber.service; do
  if [ -f "/usr/lib/systemd/user/$u" ] || [ -f "/lib/systemd/user/$u" ]; then
    ln -sf "/usr/lib/systemd/user/$u" \
      "/home/mediabridge/.config/systemd/user/default.target.wants/$u" 2>/dev/null || \
    ln -sf "/lib/systemd/user/$u" \
      "/home/mediabridge/.config/systemd/user/default.target.wants/$u" 2>/dev/null || true
  fi
done
chown -R mediabridge:audio /home/mediabridge/.config

# Create WirePlumber Chrome isolation configuration
echo "Setting up WirePlumber Chrome isolation..."
cat > /var/lib/mediabridge/.config/wireplumber/wireplumber.conf.d/50-chrome-isolation.conf << 'EOF'
{
  "wireplumber.settings": {
    "device.routes.default-sink-volume": 1.0,
    "device.routes.default-source-volume": 1.0
  },
  "wireplumber.profiles": {
    "main": {
      "monitor.access": {
        "rules": [
          {
            "matches": [
              { "application.process.binary": "~chrome" }
            ],
            "actions": {
              "update-props": {
                "media.blocked": false,
                "default_permissions": "rx",
                "media.allowed": ["intercom-speaker", "intercom-microphone.monitor"]
              }
            }
          }
        ]
      }
    }
  }
}
EOF

chown -R mediabridge:audio /var/lib/mediabridge/.config

# Update all helper scripts
echo "Updating helper scripts (removing legacy /run/pipewire usage)..."
for script in /usr/local/bin/media-bridge-* /usr/local/bin/ndi-display-*; do
  [ -f "$script" ] || continue
  sed -i '/XDG_RUNTIME_DIR=\/run\/pipewire/d' "$script" 2>/dev/null || true
  sed -i '/PIPEWIRE_RUNTIME_DIR=\/run\/pipewire/d' "$script" 2>/dev/null || true
  sed -i '/PULSE_RUNTIME_PATH=\/run\/pipewire\/pulse/d' "$script" 2>/dev/null || true
done

# Disable old system services
echo "Disabling old system services..."
systemctl disable pipewire-system 2>/dev/null || true
systemctl disable pipewire-pulse-system 2>/dev/null || true
systemctl disable wireplumber-system 2>/dev/null || true

# Enable new user services
echo "PipeWire user services enabled via wants symlinks"

# Update systemd service files
echo "Updating systemd service files..."

echo "Installing user intercom service (if present)..."
if [ -f /etc/systemd/user/media-bridge-intercom.service ]; then
  ln -sf /etc/systemd/user/media-bridge-intercom.service \
        /home/mediabridge/.config/systemd/user/default.target.wants/media-bridge-intercom.service
  chown -R mediabridge:audio /home/mediabridge/.config
fi

# Update global environment
echo "Global environment unchanged (user session provides XDG_RUNTIME_DIR)"

# Reload systemd
echo "Reloading systemd configuration..."
systemctl daemon-reload

# Start user session
echo "Ensure mediabridge user session lingering is enabled (loginctl enable-linger mediabridge)"

# Wait for PipeWire to start
echo "Waiting for PipeWire to start..."
sleep 5

# Verify PipeWire is running
if sudo -u mediabridge systemctl --user is-active pipewire.service >/dev/null 2>&1; then
    echo "✓ PipeWire is running as mediabridge user"
else
    echo "⚠ PipeWire may not be running. Check with: sudo -u mediabridge systemctl --user status pipewire"
fi

# Start Media Bridge services
echo "Starting Media Bridge services..."
sudo -u mediabridge systemctl --user start media-bridge-intercom 2>/dev/null || true
systemctl start ndi-capture 2>/dev/null || true

echo ""
echo "========================================="
echo "Migration Complete!"
echo "========================================="
echo ""
echo "PipeWire has been migrated from root to the mediabridge user."
echo ""
echo "Please reboot the system to ensure all changes take effect:"
echo "  sudo reboot"
echo ""
echo "After reboot, verify services with:"
echo "  systemctl status media-bridge-intercom"
echo "  systemctl --user -M mediabridge@ status pipewire"
echo "  sudo -u mediabridge pactl info"
echo ""
