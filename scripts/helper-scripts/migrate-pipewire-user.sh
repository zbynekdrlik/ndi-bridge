#!/bin/bash
# Migration script for existing Media Bridge deployments
# Migrates PipeWire from root to mediabridge user

set -e

echo "========================================="
echo "Media Bridge PipeWire User Migration"
echo "========================================="
echo ""
echo "This script will migrate your PipeWire audio system"
echo "from running as root to running as the mediabridge user."
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
echo "Creating mediabridge user..."
if ! id -u mediabridge >/dev/null 2>&1; then
    # Create required groups first
    groupadd -r pipewire 2>/dev/null || true
    groupadd -r render 2>/dev/null || true
    groupadd -r input 2>/dev/null || true
    
    # Create mediabridge user
    useradd --system --uid 999 --gid audio \
            --groups pipewire,video,input,render \
            --home /var/lib/mediabridge \
            --shell /bin/false \
            --comment "Media Bridge System User" \
            mediabridge
    echo "User mediabridge created with UID 999"
else
    echo "User mediabridge already exists"
    # Ensure user is in correct groups
    usermod -a -G pipewire,video,input,render,audio mediabridge
fi

# Enable persistent user session
echo "Enabling persistent user session..."
loginctl enable-linger mediabridge

# Create directories
echo "Creating required directories..."
mkdir -p /run/pipewire
mkdir -p /var/lib/mediabridge
mkdir -p /var/lib/mediabridge/.config/systemd/user
mkdir -p /var/lib/mediabridge/.config/wireplumber/wireplumber.conf.d
mkdir -p /var/run/ndi-display
mkdir -p /var/run/media-bridge

# Set ownership
chown mediabridge:audio /run/pipewire
chown -R mediabridge:audio /var/lib/mediabridge
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
d /run/pipewire 0755 mediabridge audio -
d /run/user/999 0700 mediabridge audio -
d /var/lib/mediabridge 0755 mediabridge audio -
d /var/run/ndi-display 0755 mediabridge audio -
d /var/run/media-bridge 0755 mediabridge audio -
EOF

# Apply tmpfiles configuration
systemd-tmpfiles --create /etc/tmpfiles.d/mediabridge.conf

# Create PipeWire user service overrides
echo "Configuring PipeWire user services..."
mkdir -p /var/lib/mediabridge/.config/systemd/user/pipewire.service.d
cat > /var/lib/mediabridge/.config/systemd/user/pipewire.service.d/override.conf << 'EOF'
[Service]
ExecStartPost=/bin/sh -c 'sleep 1; mount --bind /run/user/999/pipewire-0 /run/pipewire/pipewire-0 2>/dev/null || true'
ExecStopPost=-/bin/umount /run/pipewire/pipewire-0
LimitNOFILE=32768
LimitNPROC=32768
LimitMEMLOCK=infinity
Restart=on-failure
RestartSec=5s
EOF

mkdir -p /var/lib/mediabridge/.config/systemd/user/pipewire-pulse.service.d
cat > /var/lib/mediabridge/.config/systemd/user/pipewire-pulse.service.d/override.conf << 'EOF'
[Service]
ExecStartPost=/bin/sh -c 'sleep 1; mount --bind /run/user/999/pulse /run/pipewire/pulse 2>/dev/null || true'
ExecStopPost=-/bin/umount /run/pipewire/pulse
LimitNOFILE=32768
LimitNPROC=32768
EOF

# Set ownership
chown -R mediabridge:audio /var/lib/mediabridge/.config

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
echo "Updating helper scripts..."
for script in /usr/local/bin/media-bridge-*; do
    if [ -f "$script" ]; then
        # Update XDG_RUNTIME_DIR
        sed -i 's|export XDG_RUNTIME_DIR=/run/user/0|export XDG_RUNTIME_DIR=/run/pipewire|g' "$script"
        sed -i 's|XDG_RUNTIME_DIR=/run/user/0|XDG_RUNTIME_DIR=/run/pipewire|g' "$script"
        
        # Add new environment variables after XDG_RUNTIME_DIR
        if grep -q "export XDG_RUNTIME_DIR=/run/pipewire" "$script"; then
            sed -i '/export XDG_RUNTIME_DIR=\/run\/pipewire/a export PIPEWIRE_RUNTIME_DIR=/run/pipewire\nexport PULSE_RUNTIME_PATH=/run/pipewire/pulse' "$script"
        fi
        
        # Update Chrome profile path
        sed -i 's|/tmp/chrome-vdo-profile|/var/lib/mediabridge/chrome-profile|g' "$script"
        sed -i 's|/opt/chrome-vdo-profile|/var/lib/mediabridge/chrome-profile|g' "$script"
    fi
done

# Update ndi-display-launcher
if [ -f /usr/local/bin/ndi-display-launcher ]; then
    sed -i 's|export XDG_RUNTIME_DIR="/run/user/0"|export XDG_RUNTIME_DIR="/run/pipewire"|g' /usr/local/bin/ndi-display-launcher
    sed -i '/export XDG_RUNTIME_DIR/a export PIPEWIRE_RUNTIME_DIR="/run/pipewire"\nexport PULSE_RUNTIME_PATH="/run/pipewire/pulse"' /usr/local/bin/ndi-display-launcher
    sed -i 's|pipewire-system\.service|user@999.service|g' /usr/local/bin/ndi-display-launcher
fi

# Disable old system services
echo "Disabling old system services..."
systemctl disable pipewire-system 2>/dev/null || true
systemctl disable pipewire-pulse-system 2>/dev/null || true
systemctl disable wireplumber-system 2>/dev/null || true

# Enable new user services
echo "Enabling PipeWire user services..."
sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user enable pipewire.service
sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user enable pipewire-pulse.service
sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user enable wireplumber.service

# Update systemd service files
echo "Updating systemd service files..."

# Update media-bridge-intercom.service
if [ -f /etc/systemd/system/media-bridge-intercom.service ]; then
    sed -i 's|User=root|User=mediabridge|g' /etc/systemd/system/media-bridge-intercom.service
    sed -i 's|After=.*pipewire-system.*|After=network-online.target|g' /etc/systemd/system/media-bridge-intercom.service
    sed -i '/^User=mediabridge/a Group=audio\n\n# Environment for PipeWire socket access\nEnvironment="XDG_RUNTIME_DIR=/run/pipewire"\nEnvironment="PIPEWIRE_RUNTIME_DIR=/run/pipewire"\nEnvironment="PULSE_RUNTIME_PATH=/run/pipewire/pulse"\nEnvironment="CHROME_USER_DATA_DIR=/var/lib/mediabridge/chrome-profile"' /etc/systemd/system/media-bridge-intercom.service
fi

# Update ndi-display@.service
if [ -f /etc/systemd/system/ndi-display@.service ]; then
    sed -i 's|User=root|User=mediabridge|g' /etc/systemd/system/ndi-display@.service
    sed -i 's|After=.*pipewire-system.*|After=network.target|g' /etc/systemd/system/ndi-display@.service
    sed -i '/^User=mediabridge/a Group=audio' /etc/systemd/system/ndi-display@.service
    sed -i 's|XDG_RUNTIME_DIR=/run/user/0|XDG_RUNTIME_DIR=/run/pipewire|g' /etc/systemd/system/ndi-display@.service
    sed -i '/XDG_RUNTIME_DIR/a Environment="PIPEWIRE_RUNTIME_DIR=/run/pipewire"' /etc/systemd/system/ndi-display@.service
fi

# Update ndi-capture.service
if [ -f /etc/systemd/system/ndi-capture.service ]; then
    sed -i '/^\[Service\]/a User=mediabridge\nGroup=audio\n\n# Environment for PipeWire socket access\nEnvironment="XDG_RUNTIME_DIR=/run/pipewire"\nEnvironment="PIPEWIRE_RUNTIME_DIR=/run/pipewire"\nEnvironment="LD_LIBRARY_PATH=/usr/local/lib"' /etc/systemd/system/ndi-capture.service
fi

# Update global environment
echo "Updating global environment..."
sed -i 's|XDG_RUNTIME_DIR=/run/user/0|XDG_RUNTIME_DIR=/run/pipewire|g' /etc/environment
if ! grep -q "PIPEWIRE_RUNTIME_DIR" /etc/environment; then
    echo "PIPEWIRE_RUNTIME_DIR=/run/pipewire" >> /etc/environment
    echo "PULSE_RUNTIME_PATH=/run/pipewire/pulse" >> /etc/environment
fi

# Reload systemd
echo "Reloading systemd configuration..."
systemctl daemon-reload

# Start user session
echo "Starting mediabridge user session..."
systemctl start user@999.service

# Wait for PipeWire to start
echo "Waiting for PipeWire to start..."
sleep 5

# Verify PipeWire is running
if sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user is-active pipewire.service >/dev/null 2>&1; then
    echo "✓ PipeWire is running as mediabridge user"
else
    echo "⚠ PipeWire may not be running. Check with: systemctl --user -M mediabridge@ status pipewire"
fi

# Start Media Bridge services
echo "Starting Media Bridge services..."
systemctl start media-bridge-intercom
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