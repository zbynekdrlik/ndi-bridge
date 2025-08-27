#!/bin/bash
# Quick deployment script for VDO.Ninja intercom updates
# Usage: ./quick-deploy-intercom.sh [IP_ADDRESS]

set -e

IP="${1:-10.77.9.140}"
PASSWORD="newlevel"

echo "=== Quick Deploy VDO.Ninja Intercom to $IP ==="

# Check connectivity
echo "Checking connectivity..."
if ! ping -c 1 $IP > /dev/null 2>&1; then
    echo "Error: Cannot reach device at $IP"
    exit 1
fi

echo "Stopping service..."
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$IP "systemctl stop vdo-ninja-intercom || true"

echo "Deploying intercom scripts..."
sshpass -p $PASSWORD scp -o LogLevel=ERROR scripts/helper-scripts/vdo-ninja-intercom-pipewire root@$IP:/usr/local/bin/
sshpass -p $PASSWORD scp -o LogLevel=ERROR scripts/helper-scripts/vdo-ninja-intercom-launcher root@$IP:/usr/local/bin/
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$IP "chmod +x /usr/local/bin/vdo-ninja-intercom*"

echo "Deploying service file..."
sshpass -p $PASSWORD scp -o LogLevel=ERROR scripts/helper-scripts/vdo-ninja-intercom.service root@$IP:/etc/systemd/system/

echo "Reloading systemd and starting service..."
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$IP "systemctl daemon-reload && systemctl enable vdo-ninja-intercom && systemctl start vdo-ninja-intercom"

echo "Checking service status..."
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$IP "systemctl status vdo-ninja-intercom --no-pager -l"

echo ""
echo "=== Testing VNC Access ==="
echo "VNC should be available at: $IP:5999"
echo "Testing port..."
nc -zv $IP 5999 2>&1 | grep -E "(succeeded|open)" && echo "VNC port is open!" || echo "VNC port not accessible"

echo ""
echo "=== Checking Chrome Process ==="
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$IP "pgrep -f chrome > /dev/null && echo 'Chrome is running' || echo 'Chrome is NOT running'"

echo ""
echo "=== Recent Logs ==="
sshpass -p $PASSWORD ssh -o LogLevel=ERROR root@$IP "journalctl -u vdo-ninja-intercom -n 20 --no-pager"

echo ""
echo "Deployment complete!"
echo "Connect to VNC at: $IP:5999 (no password)"
