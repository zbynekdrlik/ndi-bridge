#!/bin/bash
# TTY configuration module

configure_ttys() {
    log "Configuring TTY consoles..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << EOFTTY

# Configure TTY1 to show NDI logs automatically using systemd service
cat > /etc/systemd/system/ndi-logs@.service << 'EOFLOGSERVICE'
[Unit]
Description=NDI Logs on %I
After=systemd-user-sessions.service plymouth-quit-wait.service
After=rc-local.service
Before=getty.target
IgnoreOnIsolate=yes

[Service]
Type=idle
ExecStart=/usr/local/bin/ndi-bridge-show-logs
Restart=always
User=root
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/%I
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
UtmpIdentifier=%I
UtmpMode=login

[Install]
WantedBy=getty.target
DefaultInstance=tty1
EOFLOGSERVICE

# Disable getty on tty1 and enable our service
if command -v systemctl >/dev/null 2>&1; then
    systemctl disable getty@tty1
    systemctl enable ndi-logs@tty1
else
    update-rc.d getty@tty1 disable 2>/dev/null || true
    update-rc.d ndi-logs@tty1 enable 2>/dev/null || true
fi

# Configure TTY2 with welcome screen and auto-login
mkdir -p /etc/systemd/system/getty@tty2.service.d
cat > /etc/systemd/system/getty@tty2.service.d/override.conf << EOFGETTY2
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \\\$TERM
Type=idle
EOFGETTY2

# Enable normal login on other TTYs (3-6)
for tty in 3 4 5 6; do
    mkdir -p /etc/systemd/system/getty@tty${tty}.service.d
    cat > /etc/systemd/system/getty@tty${tty}.service.d/override.conf << EOFGETTY
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear %I \\\$TERM
Type=idle
EOFGETTY
    # Enable the getty service for this TTY
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable getty@tty${tty}
    else
        update-rc.d getty@tty${tty} enable 2>/dev/null || true
    fi
done

# Enable TTY2 only (TTY1 uses ndi-logs service)
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable getty@tty2
else
    update-rc.d getty@tty2 enable 2>/dev/null || true
fi

# Create .profile that shows welcome
cat > /root/.profile << 'EOFPROFILE'
# Set TERM for TTY
export TERM=linux

# Run welcome in auto-refresh mode
/usr/local/bin/ndi-bridge-welcome-loop
EOFPROFILE

# Create auto-refreshing welcome loop script
cat > /usr/local/bin/ndi-bridge-welcome-loop << 'EOFWELCOMELOOP'
#!/bin/bash
# Auto-refreshing welcome screen
while true; do
    /usr/local/bin/ndi-bridge-welcome
    # Wait for key press or timeout after 5 seconds
    read -t 5 -n 1 -s -r -p "" key
    if [[ \$? -eq 0 ]]; then
        # Key was pressed, clear screen and give shell
        clear
        echo "Type 'ndi-bridge-welcome-loop' to return to auto-refreshing menu"
        echo ""
        break
    fi
    # No key pressed, loop continues and refreshes screen
done
EOFWELCOMELOOP
chmod +x /usr/local/bin/ndi-bridge-welcome-loop

# Install helper scripts inside chroot
mkdir -p /usr/local/bin

# Create ndi-bridge-show-logs script
cat > /usr/local/bin/ndi-bridge-show-logs << 'EOFSHOWLOGS'
#!/bin/bash
# Show NDI Bridge logs on TTY1
clear
echo "=== NDI Bridge Live Logs ==="
echo "Switch to TTY2 (Alt+F2) for system menu"
echo "Press Ctrl+C to stop following logs"
echo ""
journalctl -u ndi-bridge -f --no-pager
EOFSHOWLOGS
chmod +x /usr/local/bin/ndi-bridge-show-logs

# Create ndi-bridge-welcome script
cat > /usr/local/bin/ndi-bridge-welcome << 'EOFWELCOME'
#!/bin/bash
# Show NDI Bridge welcome screen
clear
echo -e "\\033[1;32m"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                      NDI Bridge System                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "\\033[0m"
echo -e "\\033[1;36mSystem Information:\\033[0m"
echo "  Hostname:   \\$(hostname)"
# Get IP address - try br0 first, then any other interface
IP_ADDR=\\$(ip -4 addr show dev br0 2>/dev/null | awk '/inet/ {print \\$2}' | cut -d/ -f1 | head -1)
if [ -z "\\$IP_ADDR" ]; then
    # Try any interface except lo
    IP_ADDR=\\$(ip -4 addr show | grep -v " lo" | awk '/inet/ {print \\$2}' | cut -d/ -f1 | grep -v "^127\\\\." | head -1)
fi
if [ -z "\\$IP_ADDR" ]; then
    echo -e "  IP Address: \\033[1;33mWaiting for DHCP...\\033[0m"
    # Show network status
    LINK_STATUS=\\$(ip link show | grep -E "^[0-9]+: (en|eth)" | grep -c "state UP")
    if [ "\\$LINK_STATUS" -eq 0 ]; then
        echo -e "  Link Status: \\033[1;31mNo cable connected\\033[0m"
    else
        echo -e "  Link Status: \\033[1;32mCable connected\\033[0m - acquiring address..."
    fi
else
    echo -e "  IP Address: \\033[1;32m\\$IP_ADDR\\033[0m"
fi
echo "  Uptime:     \\$(uptime -p)"
echo ""
echo -e "\\033[1;36mSoftware Versions:\\033[0m"
echo "  NDI-Bridge: \\$(/opt/ndi-bridge/ndi-bridge --version 2>&1 | head -1 | awk '{for(i=1;i<=NF;i++) if(\\$i ~ /[0-9]+\\\\.[0-9]+\\\\.[0-9]+/) print \\$i}' || echo 'Unknown')"
echo "  Build Script: \\$(cat /etc/ndi-bridge/build-script-version 2>/dev/null || echo 'Unknown')"
echo ""
echo -e "\\033[1;36mNetwork Configuration:\\033[0m"
echo "  • Both ethernet ports are bridged (br0)"
echo "  • Connect cable to either port"
echo "  • Chain devices through second port"
echo ""
echo -e "\\033[1;36mAvailable Commands:\\033[0m"
echo -e "  \\033[1;33mndi-bridge-info\\033[0m         - Display system status"
echo -e "  \\033[1;33mndi-bridge-set-name\\033[0m     - Set device name (hostname & NDI)"
echo -e "  \\033[1;33mndi-bridge-update\\033[0m       - Update NDI binary"
echo -e "  \\033[1;33mndi-bridge-logs\\033[0m         - View NDI logs"
echo -e "  \\033[1;33mndi-bridge-netstat\\033[0m      - Network bridge status"
echo -e "  \\033[1;33mndi-bridge-netmon\\033[0m       - Network bandwidth monitor"
echo -e "  \\033[1;33mndi-bridge-rw\\033[0m           - Mount filesystem read-write"
echo -e "  \\033[1;33mndi-bridge-ro\\033[0m           - Mount filesystem read-only"
echo -e "  \\033[1;33mndi-bridge-help\\033[0m         - Show all commands"
echo -e "  \\033[1;33mndi-bridge-welcome-loop\\033[0m - Return to auto-refresh menu"
echo ""
echo -e "\\033[1;36mConsole Switching:\\033[0m"
echo "  • TTY1 (Alt+F1) - Live NDI logs"
echo "  • TTY2 (Alt+F2) - This menu"
echo "  • TTY3-6 (Alt+F3-F6) - Additional terminals"
echo ""
echo -e "\\033[1;32mNDI Service:\\033[0m"
systemctl is-active ndi-bridge >/dev/null 2>&1 && echo -e "  Status: \\033[1;32m●\\033[0m Running" || echo -e "  Status: \\033[1;31m●\\033[0m Stopped"
echo ""
echo -e "\\033[0;90mPress any key for shell prompt (auto-refresh every 5s)\\033[0m"
EOFWELCOME
chmod +x /usr/local/bin/ndi-bridge-welcome

EOFTTY
}

export -f configure_ttys