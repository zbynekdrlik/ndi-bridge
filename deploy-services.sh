#!/bin/bash

# Deploy service files to test box
BOX_IP="${1:-10.77.8.110}"

echo "Deploying PipeWire service files to $BOX_IP..."

# Stop services first
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "systemctl stop pipewire-system pipewire-pulse-system wireplumber-system media-bridge-intercom 2>/dev/null || true"

# Copy service files
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/pipewire-system.service root@$BOX_IP:/etc/systemd/system/
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/pipewire-pulse-system.service root@$BOX_IP:/etc/systemd/system/
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/wireplumber-system.service root@$BOX_IP:/etc/systemd/system/

# Copy config files
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "mkdir -p /etc/pipewire/pipewire.conf.d /etc/wireplumber/main.lua.d"
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/pipewire-conf.d/* root@$BOX_IP:/etc/pipewire/pipewire.conf.d/
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/wireplumber-conf.d/* root@$BOX_IP:/etc/wireplumber/main.lua.d/

# Copy audio manager
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/media-bridge-audio-manager root@$BOX_IP:/usr/local/bin/
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "chmod +x /usr/local/bin/media-bridge-audio-manager"

# Copy updated intercom script
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/media-bridge-intercom-pipewire root@$BOX_IP:/usr/local/bin/media-bridge-intercom
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "chmod +x /usr/local/bin/media-bridge-intercom"

# Reload systemd and start services
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "systemctl daemon-reload"
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "systemctl start pipewire-system pipewire-pulse-system wireplumber-system"

# Check status
echo "Checking service status..."
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "systemctl is-active pipewire-system pipewire-pulse-system wireplumber-system"

echo "Deployment complete!"