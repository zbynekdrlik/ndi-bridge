#!/bin/bash
# Fix script for NDI-Bridge USB issues

set -e

USB_MOUNT="/mnt/usb"
USB_DEVICE="${1:-/dev/sdb}"

echo "=== NDI-Bridge USB Fix Script ==="
echo "This will fix issues with the USB system"
echo ""

# Mount USB
echo "Mounting USB..."
mkdir -p $USB_MOUNT
mount ${USB_DEVICE}2 $USB_MOUNT || { echo "Failed to mount USB"; exit 1; }
mount ${USB_DEVICE}1 $USB_MOUNT/boot/efi

# Fix 1: Update the profile to not auto-follow logs
echo "Fixing console auto-login..."
cat > $USB_MOUNT/root/.profile << 'EOF'
# Show NDI Bridge status on login
clear
echo "=== NDI Bridge System ==="
echo "IP: $(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1 || echo 'No IP yet')"
echo ""
echo "Commands:"
echo "  ndi-bridge-help    - Show all commands"
echo "  ndi-bridge-info    - System status"
echo "  ndi-bridge-logs    - Follow NDI logs"
echo "  ndi-bridge-rw      - Mount filesystem read-write"
echo ""
echo "Network tools: ip, ss, nstat (route command needs net-tools package)"
echo ""
EOF

# Fix 2: Create log directory creation in run script
echo "Fixing log directory creation..."
sed -i '1a\
# Create log directory if it does not exist\
mkdir -p /var/log/ndi-bridge 2>/dev/null || true' $USB_MOUNT/opt/ndi-bridge/run.sh

# Fix 3: Add helper to view logs
cat > $USB_MOUNT/usr/local/bin/ndi-bridge-logs << 'EOF'
#!/bin/bash
echo "Following NDI Bridge logs (Ctrl+C to exit)..."
journalctl -u ndi-bridge -f --no-pager
EOF
chmod +x $USB_MOUNT/usr/local/bin/ndi-bridge-logs

# Fix 4: Add net-tools to package list for future builds
echo "Adding net-tools to package list..."
sed -i '/iproute2/a\    net-tools \\' $USB_MOUNT/tmp/setup.sh 2>/dev/null || true

# Fix 5: Create a notice about libstdc++ issue
cat > $USB_MOUNT/etc/motd << 'EOF'

=== IMPORTANT NOTICE ===
The NDI-Bridge binary requires a newer libstdc++ (GLIBCXX_3.4.32) than available.
To fix this issue:
1. Mount filesystem read-write: ndi-bridge-rw
2. Update the binary with one compiled on Ubuntu 22.04
3. Or upgrade libstdc++6 from a newer Ubuntu release
========================

EOF

# Fix 6: Add getty on other TTYs
echo "Enabling login on other TTYs..."
for tty in 2 3 4 5 6; do
    mkdir -p $USB_MOUNT/etc/systemd/system/getty@tty${tty}.service.d
    cat > $USB_MOUNT/etc/systemd/system/getty@tty${tty}.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear %I \$TERM
Type=idle
EOF
done

# Fix 7: Temporarily disable NDI-Bridge service to stop crash loop
echo "Disabling NDI-Bridge service temporarily..."
rm -f $USB_MOUNT/etc/systemd/system/multi-user.target.wants/ndi-bridge.service

echo ""
echo "=== Fixes Applied ==="
echo "1. Console no longer auto-follows logs"
echo "2. Log directory will be created on tmpfs"
echo "3. Added 'ndi-bridge-logs' command"
echo "4. Enabled login on TTY2-6"
echo "5. Disabled NDI-Bridge service (due to libstdc++ issue)"
echo ""
echo "To fix the libstdc++ issue, you need to either:"
echo "- Compile NDI-Bridge on Ubuntu 22.04"
echo "- Copy newer libstdc++ libraries to the USB"
echo ""

# Unmount
sync
umount $USB_MOUNT/boot/efi
umount $USB_MOUNT

echo "Done! Reboot the USB system to apply changes."