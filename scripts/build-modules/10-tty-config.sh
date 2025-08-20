#!/bin/bash
# TTY configuration module

configure_ttys() {
    log "Configuring TTY consoles..."
    
    cat >> /mnt/usb/tmp/configure-system.sh << 'EOFTTY'

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
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
Type=idle
EOFGETTY2

# Enable normal login on other TTYs (3-6)
for tty in 3 4 5 6; do
    mkdir -p /etc/systemd/system/getty@tty${tty}.service.d
    cat > /etc/systemd/system/getty@tty${tty}.service.d/override.conf << EOFGETTY
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear %I \$TERM
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

# All helper scripts (welcome, show-logs, welcome-loop) are installed from
# helper-scripts directory - don't create them inline here!
# Just ensure they're executable
chmod +x /usr/local/bin/ndi-bridge-show-logs 2>/dev/null || true
chmod +x /usr/local/bin/ndi-bridge-welcome 2>/dev/null || true
chmod +x /usr/local/bin/ndi-bridge-welcome-loop 2>/dev/null || true

# Old inline scripts have been completely removed.
# All scripts are now maintained in scripts/helper-scripts/ directory

EOFTTY
}

export -f configure_ttys
