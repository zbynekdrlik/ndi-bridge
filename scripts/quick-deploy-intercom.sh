#!/bin/bash

# Quick deployment script for intercom feature to test box
# Usage: ./quick-deploy-intercom.sh [IP_ADDRESS]

BOX_IP="${1:-10.77.9.143}"
PASSWORD="newlevel"

echo "Deploying intercom feature to $BOX_IP..."
echo "=================================="

# Check if box is reachable
if ! ping -c 1 -W 2 $BOX_IP >/dev/null 2>&1; then
    echo "Error: Cannot reach $BOX_IP"
    exit 1
fi

# Make filesystem writable
echo "Making filesystem writable..."
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$BOX_IP "ndi-bridge-rw"

# Create directories
echo "Creating directories..."
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$BOX_IP "mkdir -p /opt/ndi-bridge /etc/ndi-bridge /etc/systemd/system"

# Copy intercom script
echo "Copying intercom script..."
sshpass -p $PASSWORD scp -o LogLevel=ERROR scripts/helper-scripts/ndi-bridge-intercom root@$BOX_IP:/opt/ndi-bridge/
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$BOX_IP "chmod +x /opt/ndi-bridge/ndi-bridge-intercom"

# Copy helper scripts
echo "Copying helper scripts..."
for script in ndi-bridge-intercom-status ndi-bridge-intercom-logs \
              ndi-bridge-intercom-restart ndi-bridge-intercom-enable \
              ndi-bridge-intercom-disable; do
    sshpass -p $PASSWORD scp -o LogLevel=ERROR scripts/helper-scripts/$script root@$BOX_IP:/opt/ndi-bridge/
    sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$BOX_IP "chmod +x /opt/ndi-bridge/$script"
    # Create symlink
    sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$BOX_IP "ln -sf /opt/ndi-bridge/$script /usr/local/bin/$script"
done

# Copy config file
echo "Copying config file..."
sshpass -p $PASSWORD scp -o LogLevel=ERROR scripts/helper-scripts/intercom.conf root@$BOX_IP:/etc/ndi-bridge/

# Copy systemd service
echo "Copying systemd service..."
sshpass -p $PASSWORD scp -o LogLevel=ERROR scripts/helper-scripts/ndi-bridge-intercom.service root@$BOX_IP:/etc/systemd/system/

# Copy updated welcome script
echo "Updating welcome screen..."
sshpass -p $PASSWORD scp -o LogLevel=ERROR scripts/helper-scripts/ndi-bridge-welcome root@$BOX_IP:/opt/ndi-bridge/

# Install chromium if not present
echo "Checking for chromium..."
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$BOX_IP "
if ! which chromium-browser >/dev/null 2>&1 && ! which chromium >/dev/null 2>&1; then
    echo 'Installing chromium...'
    apt-get update -qq
    apt-get install -y -qq chromium-browser 2>/dev/null || apt-get install -y -qq chromium 2>/dev/null
fi
"

# Reload systemd and enable service
echo "Enabling intercom service..."
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$BOX_IP "
systemctl daemon-reload
systemctl enable ndi-bridge-intercom
systemctl restart ndi-bridge-intercom
"

# Return filesystem to read-only
echo "Returning filesystem to read-only..."
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$BOX_IP "ndi-bridge-ro"

# Wait for service to start
echo "Waiting for service to start..."
sleep 5

# Check status
echo ""
echo "Checking intercom status..."
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$BOX_IP "
if systemctl is-active --quiet ndi-bridge-intercom; then
    echo '✓ Intercom service is running'
    echo ''
    echo 'Process information:'
    pgrep -f 'vdo.ninja\|chromium.*intercom' && echo 'Chromium process found' || echo 'Chromium process not found'
    echo ''
    echo 'Recent logs:'
    journalctl -u ndi-bridge-intercom -n 10 --no-pager
else
    echo '✗ Intercom service is not running'
    echo ''
    echo 'Service status:'
    systemctl status ndi-bridge-intercom --no-pager
fi
"

echo ""
echo "Deployment complete!"
echo "You can check the status with:"
echo "  ssh root@$BOX_IP ndi-bridge-intercom-status"
echo "  ssh root@$BOX_IP ndi-bridge-intercom-logs"