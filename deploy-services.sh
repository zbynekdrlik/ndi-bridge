#!/bin/bash

# Deploy service files to test box
BOX_IP="${1:-10.77.8.110}"

echo "Deploying PipeWire user-session configuration to $BOX_IP..."

# Stop legacy system services if present
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "systemctl stop pipewire-system pipewire-pulse-system wireplumber-system media-bridge-intercom 2>/dev/null || true"

# Create mediabridge user session dirs and configs
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "mkdir -p /home/mediabridge/.config/systemd/user/default.target.wants; chown -R mediabridge:audio /home/mediabridge/.config"

# Deploy WirePlumber isolation config to user config
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/50-chrome-isolation.conf root@$BOX_IP:/home/mediabridge/.config/wireplumber/wireplumber.conf.d/
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "chown -R mediabridge:audio /home/mediabridge/.config"

# Deploy intercom user unit
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/media-bridge-intercom.service root@$BOX_IP:/etc/systemd/user/
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "ln -sf /etc/systemd/user/media-bridge-intercom.service /home/mediabridge/.config/systemd/user/default.target.wants/media-bridge-intercom.service && chown -R mediabridge:audio /home/mediabridge/.config"

# Deploy audio manager and intercom scripts
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/media-bridge-audio-manager root@$BOX_IP:/usr/local/bin/
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/media-bridge-intercom-pipewire root@$BOX_IP:/usr/local/bin/media-bridge-intercom
sshpass -p newlevel scp -o LogLevel=ERROR scripts/helper-scripts/media-bridge-intercom-launcher root@$BOX_IP:/usr/local/bin/
sshpass -p newlevel ssh -o LogLevel=ERROR root@$BOX_IP "chmod +x /usr/local/bin/media-bridge-audio-manager /usr/local/bin/media-bridge-intercom /usr/local/bin/media-bridge-intercom-launcher"

echo "Deployment complete (user-session model)."
