#!/bin/bash
# NDI-Bridge USB Linux Builder - FINAL VERSION
# Creates a complete bootable USB Linux system with NDI-Bridge
# Power failure resistant, auto-starting NDI video bridge
# Uses Ubuntu 24.04 LTS for compatibility with NDI-Bridge binary

set -e

# Configuration
USB_DEVICE="${1:-/dev/sdb}"
NDI_BINARY_PATH="$(dirname "$0")/../build/bin/ndi-bridge"
NDI_SDK_PATH="$(dirname "$0")/../../NDI SDK for Linux"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        error "This script must be run as root"
    fi
    
    # Check USB device
    if [ ! -b "$USB_DEVICE" ]; then
        error "USB device $USB_DEVICE not found"
    fi
    
    # Check NDI binary
    if [ ! -f "$NDI_BINARY_PATH" ]; then
        error "NDI-bridge binary not found at $NDI_BINARY_PATH"
    fi
    
    # Check NDI SDK
    if [ ! -d "$NDI_SDK_PATH" ]; then
        error "NDI SDK not found at $NDI_SDK_PATH"
    fi
    
    # Check required tools
    for tool in debootstrap parted mkfs.ext4 mkfs.vfat; do
        if ! command -v $tool &> /dev/null; then
            error "$tool is required but not installed"
        fi
    done
}

# Partition USB drive
partition_usb() {
    log "Partitioning USB drive $USB_DEVICE..."
    
    # Unmount any existing partitions
    umount ${USB_DEVICE}* 2>/dev/null || true
    
    # Create GPT partition table
    parted -s $USB_DEVICE mklabel gpt 2>&1 | head -20
    
    # Create EFI partition (512MB)
    parted -s $USB_DEVICE mkpart primary fat32 1MiB 513MiB 2>&1 | head -20
    parted -s $USB_DEVICE set 1 esp on 2>&1 | head -20
    
    # Create root partition (rest of disk)
    parted -s $USB_DEVICE mkpart primary ext4 513MiB 100% 2>&1 | head -20
    
    # Wait for partitions to appear
    sleep 2
    partprobe $USB_DEVICE
    sleep 2
    
    # Format partitions
    log "Formatting partitions..."
    mkfs.vfat -F32 -n EFI ${USB_DEVICE}1 2>&1 | head -20
    mkfs.ext4 -L NDIBRIDGE ${USB_DEVICE}2 2>&1 | head -20
}

# Mount filesystems
mount_filesystems() {
    log "Mounting filesystems..."
    mkdir -p /mnt/usb
    mount ${USB_DEVICE}2 /mnt/usb
    mkdir -p /mnt/usb/boot/efi
    mount ${USB_DEVICE}1 /mnt/usb/boot/efi
}

# Install base system
install_base_system() {
    log "Installing Ubuntu 24.04 base system (this will take 5-10 minutes)..."
    log "Progress: "
    debootstrap --arch=amd64 noble /mnt/usb http://archive.ubuntu.com/ubuntu/ 2>&1 | \
        while IFS= read -r line; do
            echo -n "."
        done
    echo " Done!"
}

# Configure system
configure_system() {
    log "Configuring system..."
    
    # Get UUIDs for the actual device used
    local UUID_ROOT=$(blkid -s UUID -o value ${USB_DEVICE}2)
    local UUID_EFI=$(blkid -s UUID -o value ${USB_DEVICE}1)
    
    # Create setup script
    cat > /mnt/usb/tmp/setup.sh << 'EOFSETUP'
#!/bin/bash
set -e

# Reduce dpkg warnings in chroot
export DEBIAN_FRONTEND=noninteractive

echo "=== Configuring NDI Bridge USB System (Ubuntu 24.04) ==="

# Update package list
echo "Updating package list..."
apt-get update -qq

# Install kernel and bootloader first
echo "Installing kernel and bootloader..."
apt-get install -y -qq --no-install-recommends \
    linux-image-generic \
    grub-efi-amd64 \
    initramfs-tools 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || true

# Install system packages
echo "Installing system packages..."
apt-get install -y -qq --no-install-recommends \
    systemd \
    systemd-sysv \
    udev \
    iproute2 \
    net-tools \
    bridge-utils \
    openssh-server \
    sudo \
    nano \
    wget \
    ca-certificates \
    iputils-ping \
    zstd 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || true

# Try to install DHCP client (different package names in different Ubuntu versions)
apt-get install -y -qq --no-install-recommends isc-dhcp-client 2>/dev/null || \
apt-get install -y -qq --no-install-recommends dhcpcd5 2>/dev/null || \
echo "Note: Using systemd-networkd for DHCP (default in Ubuntu 24.04)"

# Install optional packages (don't fail if unavailable)
echo "Installing optional packages..."
apt-get install -y -qq --no-install-recommends \
    libavahi-common3 \
    libavahi-client3 \
    htop 2>&1 | grep -v "^Get:\|^Fetched\|^Reading\|^Building" || true

# Try to install v4l2 tools with different package names
apt-get install -y -qq --no-install-recommends v4l-utils 2>/dev/null || \
apt-get install -y -qq --no-install-recommends v4l2-tools 2>/dev/null || \
apt-get install -y -qq --no-install-recommends v4l2loopback-utils 2>/dev/null || true

# Network monitoring tools (optional)
apt-get install -y -qq --no-install-recommends nload 2>/dev/null || true
apt-get install -y -qq --no-install-recommends iftop 2>/dev/null || true
apt-get install -y -qq --no-install-recommends bmon 2>/dev/null || true

# Set hostname
echo "ndi-bridge" > /etc/hostname
cat > /etc/hosts << EOFHOSTS
127.0.0.1 localhost
127.0.1.1 ndi-bridge
EOFHOSTS

# Set root password
echo "root:NewLevel123!" | chpasswd

# Configure network bridge for both ethernet interfaces
mkdir -p /etc/systemd/network

# Create bridge device
cat > /etc/systemd/network/10-br0.netdev << EOFBRIDGE
[NetDev]
Name=br0
Kind=bridge

[Bridge]
STP=false
EOFBRIDGE

# Configure physical interfaces to join bridge
cat > /etc/systemd/network/20-eth.network << EOFETH
[Match]
Name=en*
Name=eth*

[Network]
Bridge=br0
EOFETH

# Configure bridge for DHCP
cat > /etc/systemd/network/30-br0.network << EOFBR0
[Match]
Name=br0

[Network]
DHCP=yes
IPForward=yes

[DHCP]
RouteMetric=10
UseDomains=yes
EOFBR0

systemctl enable systemd-networkd
systemctl enable systemd-resolved

# Configure SSH
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl enable ssh
fi

# Create NDI directories
mkdir -p /opt/ndi-bridge /etc/ndi-bridge

# NDI configuration
cat > /etc/ndi-bridge/config << 'EOFCONFIG'
DEVICE="/dev/video0"
NDI_NAME=""
EOFCONFIG

# NDI runner script
cat > /opt/ndi-bridge/run.sh << 'EOFRUN'
#!/bin/bash
source /etc/ndi-bridge/config
[ -z "$NDI_NAME" ] && NDI_NAME=$(hostname)

# Create log directory if it doesn't exist (tmpfs)
mkdir -p /var/log/ndi-bridge 2>/dev/null || true

# Wait for network
while ! ping -c 1 -W 1 8.8.8.8 &> /dev/null; do
    echo "Waiting for network..."
    sleep 2
done

# Wait for video device
while [ ! -e "$DEVICE" ]; do
    echo "Waiting for $DEVICE..."
    sleep 2
done

# Main loop with restart and logging to tmpfs
while true; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting NDI Bridge: $DEVICE -> $NDI_NAME"
    if [ -w /var/log/ndi-bridge ]; then
        LD_LIBRARY_PATH=/usr/local/lib /opt/ndi-bridge/ndi-bridge "$DEVICE" "$NDI_NAME" 2>&1 | tee -a /var/log/ndi-bridge/ndi-bridge.log
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDI Bridge exited, restarting in 5 seconds..." | tee -a /var/log/ndi-bridge/ndi-bridge.log
    else
        LD_LIBRARY_PATH=/usr/local/lib /opt/ndi-bridge/ndi-bridge "$DEVICE" "$NDI_NAME" 2>&1
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDI Bridge exited, restarting in 5 seconds..."
    fi
    sleep 5
done
EOFRUN
chmod +x /opt/ndi-bridge/run.sh

# Systemd service with console output
cat > /etc/systemd/system/ndi-bridge.service << EOFSERVICE
[Unit]
Description=NDI Bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=/opt/ndi-bridge/run.sh
StandardOutput=journal+console
StandardError=journal+console
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes

[Install]
WantedBy=multi-user.target
EOFSERVICE

systemctl enable ndi-bridge

# Configure tmpfs for volatile directories
cat >> /etc/fstab << EOFTMPFS
tmpfs /tmp tmpfs defaults,noatime,mode=1777,size=256M 0 0
tmpfs /var/log tmpfs defaults,noatime,mode=0755,size=512M 0 0
tmpfs /var/tmp tmpfs defaults,noatime,mode=1777,size=64M 0 0
EOFTMPFS

# Create systemd service to setup log directories on boot
cat > /etc/systemd/system/setup-logs.service << EOFLOGSVC
[Unit]
Description=Setup log directories in tmpfs
Before=ndi-bridge.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/mkdir -p /var/log/ndi-bridge
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFLOGSVC

systemctl enable setup-logs

# Configure auto-login on TTY1 to show ndi-bridge output
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOFGETTY
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
Type=idle
EOFGETTY

# Enable normal login on other TTYs (2-6)
for tty in 2 3 4 5 6; do
    mkdir -p /etc/systemd/system/getty@tty\${tty}.service.d
    cat > /etc/systemd/system/getty@tty\${tty}.service.d/override.conf << EOFGETTY2
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear %I \$TERM
Type=idle
EOFGETTY2
done

# Create profile script to show status on console (but don't auto-follow logs)
cat > /root/.profile << EOFPROFILE
# Show NDI Bridge status on login
clear
echo "=== NDI Bridge System ==="
echo "IP: \$(ip -4 addr show dev br0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1 || echo 'No IP yet')"
echo ""
echo "Commands:"
echo "  ndi-bridge-help    - Show all commands"
echo "  ndi-bridge-info    - System status" 
echo "  ndi-bridge-logs    - Follow NDI logs"
echo ""
echo "Network: Both ethernet ports are bridged (br0)"
echo "         You can connect to either port"
echo ""
echo "Service status:"
systemctl status ndi-bridge --no-pager --lines=3 2>/dev/null || echo "Service not configured"
echo ""
EOFPROFILE

# NDI name updater (handles read-only filesystem)
cat > /usr/local/bin/ndi-bridge-set-name << 'EOFNAME'
#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Usage: ndi-bridge-set-name <name>"
    exit 1
fi
# Remount root as read-write
mount -o remount,rw /
# Update config
sed -i "s/NDI_NAME=.*/NDI_NAME=\"$1\"/" /etc/ndi-bridge/config
# Remount as read-only
mount -o remount,ro /
systemctl restart ndi-bridge
echo "NDI name set to: $1"
EOFNAME
chmod +x /usr/local/bin/ndi-bridge-set-name

# Helper to remount filesystem
cat > /usr/local/bin/ndi-bridge-rw << 'EOFRW'
#!/bin/bash
mount -o remount,rw /
echo "Filesystem mounted read-write. Use 'ndi-bridge-ro' to return to read-only."
EOFRW
chmod +x /usr/local/bin/ndi-bridge-rw

cat > /usr/local/bin/ndi-bridge-ro << 'EOFRO'
#!/bin/bash
sync
mount -o remount,ro /
echo "Filesystem mounted read-only."
EOFRO
chmod +x /usr/local/bin/ndi-bridge-ro

# Update hostname helper
cat > /usr/local/bin/ndi-bridge-set-hostname << 'EOFHOST'
#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Usage: ndi-bridge-set-hostname <hostname>"
    echo "Current hostname: $(hostname)"
    exit 1
fi

NEW_HOSTNAME="$1"

# Remount as read-write
mount -o remount,rw /

# Update hostname files
echo "$NEW_HOSTNAME" > /etc/hostname
sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOSTNAME/" /etc/hosts

# Update NDI name if not explicitly set
if grep -q 'NDI_NAME=""' /etc/ndi-bridge/config; then
    echo "Hostname will be used as NDI name"
fi

# Apply hostname immediately
hostname "$NEW_HOSTNAME"

# Remount as read-only
sync
mount -o remount,ro /

echo "Hostname changed to: $NEW_HOSTNAME"
echo "Reboot recommended for full effect"
EOFHOST
chmod +x /usr/local/bin/ndi-bridge-set-hostname

# Update ndi-bridge binary helper
cat > /usr/local/bin/ndi-bridge-update << 'EOFUPDATE'
#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Usage: ndi-bridge-update <path-to-new-binary>"
    echo "Example: ndi-bridge-update /tmp/ndi-bridge"
    exit 1
fi

NEW_BINARY="$1"

if [ ! -f "$NEW_BINARY" ]; then
    echo "Error: File not found: $NEW_BINARY"
    exit 1
fi

# Check if binary is executable
if [ ! -x "$NEW_BINARY" ]; then
    echo "Making binary executable..."
    chmod +x "$NEW_BINARY"
fi

# Stop service
echo "Stopping ndi-bridge service..."
systemctl stop ndi-bridge

# Remount as read-write
mount -o remount,rw /

# Backup old binary
echo "Backing up current binary..."
cp /opt/ndi-bridge/ndi-bridge /opt/ndi-bridge/ndi-bridge.bak

# Copy new binary
echo "Installing new binary..."
cp "$NEW_BINARY" /opt/ndi-bridge/ndi-bridge
chmod +x /opt/ndi-bridge/ndi-bridge

# Remount as read-only
sync
mount -o remount,ro /

# Start service
echo "Starting ndi-bridge service..."
systemctl start ndi-bridge

echo "Update complete!"
echo "Check status: systemctl status ndi-bridge"
EOFUPDATE
chmod +x /usr/local/bin/ndi-bridge-update

# System info helper
cat > /usr/local/bin/ndi-bridge-info << 'EOFINFO'
#!/bin/bash
echo "=== NDI Bridge System Info ==="
echo "Hostname: $(hostname)"
echo "IP Address: $(ip -4 addr show dev br0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1 || echo 'No IP yet')"
echo ""
echo "NDI Configuration:"
cat /etc/ndi-bridge/config
echo ""
echo "Service Status:"
systemctl status ndi-bridge --no-pager --lines=5 2>/dev/null || echo "Service not available"
echo ""
echo "Binary Version:"
/opt/ndi-bridge/ndi-bridge --version 2>/dev/null || echo "Version info not available"
echo ""
echo "Filesystem Status:"
mount | grep " / " | grep -q "ro" && echo "Root: read-only (protected)" || echo "Root: read-write (UNSAFE)"
EOFINFO
chmod +x /usr/local/bin/ndi-bridge-info

# Create help command to list all ndi-bridge commands
cat > /usr/local/bin/ndi-bridge-help << 'EOFHELP'
#!/bin/bash
echo "=== NDI Bridge System Commands ==="
echo ""
echo "Available commands:"
echo "  ndi-bridge-info         - Display system information and status"
echo "  ndi-bridge-set-name     - Set the NDI source name"
echo "  ndi-bridge-set-hostname - Change system hostname"  
echo "  ndi-bridge-update       - Update the ndi-bridge binary"
echo "  ndi-bridge-logs         - Follow NDI Bridge service logs"
echo "  ndi-bridge-netstat      - Show network bridge status"
echo "  ndi-bridge-netmon       - Network bandwidth monitor (if available)"
echo "  ndi-bridge-rw           - Mount filesystem read-write (for maintenance)"
echo "  ndi-bridge-ro           - Mount filesystem read-only (default)"
echo "  ndi-bridge-help         - Show this help message"
echo ""
echo "Other useful commands:"
echo "  htop                    - System resource monitor (if installed)"
echo "  nload                   - Network bandwidth monitor (if installed)"
echo "  iftop                   - Network connections monitor (if installed)"
echo "  bmon                    - Network bandwidth monitor (if installed)"
echo "  journalctl -u ndi-bridge -f  - Follow service logs"
echo "  systemctl restart ndi-bridge  - Restart the service"
echo ""
echo "Tab completion works! Type 'ndi-bridge-' and press TAB"
EOFHELP
chmod +x /usr/local/bin/ndi-bridge-help

# NDI logs viewer
cat > /usr/local/bin/ndi-bridge-logs << 'EOFLOGS'
#!/bin/bash
echo "Following NDI Bridge logs (Ctrl+C to exit)..."
journalctl -u ndi-bridge -f --no-pager
EOFLOGS
chmod +x /usr/local/bin/ndi-bridge-logs

# Network bridge status helper
cat > /usr/local/bin/ndi-bridge-netstat << 'EOFNETSTAT'
#!/bin/bash
echo "=== Network Bridge Status ==="
echo ""
echo "Bridge interfaces:"
bridge link show 2>/dev/null || ip link show type bridge
echo ""
echo "IP configuration:"
ip addr show br0 2>/dev/null || echo "Bridge not configured"
echo ""
echo "Physical interfaces:"
ip -br link show | grep -E "^(en|eth)" || echo "No ethernet interfaces found"
echo ""
echo "Bridge forwarding database:"
bridge fdb show br br0 2>/dev/null | head -20
EOFNETSTAT
chmod +x /usr/local/bin/ndi-bridge-netstat

# Network monitoring wrapper
cat > /usr/local/bin/ndi-bridge-netmon << 'EOFNETMON'
#!/bin/bash
echo "=== NDI Bridge Network Monitor ==="
echo ""
if command -v nload &> /dev/null; then
    echo "Starting network bandwidth monitor..."
    echo "Press 'q' to quit, arrow keys to switch interfaces"
    echo ""
    nload -u M
elif command -v iftop &> /dev/null; then
    echo "Starting network connections monitor..."
    echo "Press 'q' to quit"
    echo ""
    iftop
elif command -v bmon &> /dev/null; then
    echo "Starting bandwidth monitor..."
    echo "Press 'q' to quit"
    echo ""
    bmon
else
    echo "No network monitoring tools installed."
    echo "Try: apt-get install nload iftop bmon"
fi
EOFNETMON
chmod +x /usr/local/bin/ndi-bridge-netmon

# Configure GRUB with 2 second timeout for fast boot
cat > /etc/default/grub << EOFGRUB
GRUB_DEFAULT=0
GRUB_TIMEOUT=2
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="NDI Bridge Linux"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX=""
EOFGRUB

# Configure ldconfig for NDI
echo "/usr/local/lib" > /etc/ld.so.conf.d/ndi.conf
ldconfig

# Reduce swappiness
echo "vm.swappiness=10" >> /etc/sysctl.conf

# Configure systemd for faster boot
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/10-timeout.conf << EOFTIMEOUT
[Manager]
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=10s
EOFTIMEOUT

echo "=== Setup complete ==="
EOFSETUP

    # Now add the fstab entries with the actual UUIDs
    cat >> /mnt/usb/tmp/setup.sh << EOFFSTAB

# Create fstab with actual device UUIDs
cat > /etc/fstab << EOFFSTAB2
UUID=$UUID_ROOT / ext4 ro,noatime,errors=remount-ro 0 1
UUID=$UUID_EFI /boot/efi vfat umask=0077 0 1
EOFFSTAB2

# Configure power failure resistance
# Set filesystem to journal data mode
tune2fs -o journal_data /dev/disk/by-uuid/$UUID_ROOT 2>/dev/null || true

# Install GRUB
echo "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=NDIBRIDGE --removable 2>&1 | head -50
update-grub 2>&1 | head -50

# Update initramfs
update-initramfs -u -k all 2>&1 | head -50

EOFFSTAB

    chmod +x /mnt/usb/tmp/setup.sh
}

# Copy NDI files
copy_ndi_files() {
    log "Copying NDI files..."
    
    # Create directories first
    mkdir -p /mnt/usb/opt/ndi-bridge
    
    # Copy NDI binary
    cp "$NDI_BINARY_PATH" /mnt/usb/opt/ndi-bridge/
    chmod +x /mnt/usb/opt/ndi-bridge/ndi-bridge
    
    # Copy NDI libraries
    mkdir -p /mnt/usb/usr/local/lib
    cp "$NDI_SDK_PATH/lib/x86_64-linux-gnu/libndi.so.6.2.0" /mnt/usb/usr/local/lib/
    cd /mnt/usb/usr/local/lib
    ln -s libndi.so.6.2.0 libndi.so.6
    ln -s libndi.so.6 libndi.so
    cd - > /dev/null
}

# Run setup in chroot
run_chroot_setup() {
    log "Running setup in chroot (this will take 5-10 minutes)..."
    
    # Mount necessary filesystems
    mount --bind /dev /mnt/usb/dev
    mount --bind /dev/pts /mnt/usb/dev/pts
    mount --bind /proc /mnt/usb/proc
    mount --bind /sys /mnt/usb/sys
    
    # Set up environment to reduce warnings
    export DEBIAN_FRONTEND=noninteractive
    
    # Run setup script
    chroot /mnt/usb /tmp/setup.sh 2>&1 | \
        while IFS= read -r line; do
            # Filter out verbose package installation output and known warnings
            if [[ ! "$line" =~ ^(Get:|Fetched|Reading|Building|Selecting|Preparing|Unpacking|Setting) ]] && \
               [[ ! "$line" =~ "dpkg-preconfigure: unable to re-open stdin" ]] && \
               [[ ! "$line" =~ "E: Can not write log" ]]; then
                echo "$line"
            fi
        done
    
    # Unmount
    umount /mnt/usb/dev/pts
    umount /mnt/usb/dev
    umount /mnt/usb/proc
    umount /mnt/usb/sys
}

# Cleanup
cleanup() {
    log "Cleaning up..."
    rm -f /mnt/usb/tmp/setup.sh
    sync
}

# Unmount
unmount_all() {
    log "Unmounting filesystems..."
    umount /mnt/usb/boot/efi || true
    umount /mnt/usb || true
}

# Main execution
main() {
    log "Starting NDI-Bridge USB Linux Builder (FINAL VERSION)"
    log "Target device: $USB_DEVICE"
    
    check_prerequisites
    
    # Confirm with user
    warn "This will ERASE ALL DATA on $USB_DEVICE"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        error "Aborted by user"
    fi
    
    partition_usb
    mount_filesystems
    install_base_system
    configure_system
    copy_ndi_files
    run_chroot_setup
    cleanup
    unmount_all
    
    log "Build complete! You can now boot from the USB drive."
    log "Default credentials: root / NewLevel123!"
    log ""
    log "The system will:"
    log "  - Boot automatically"
    log "  - Get IP via DHCP"
    log "  - Start NDI-Bridge automatically"
    log "  - Show live logs on console"
    log ""
    log "SSH access: ssh root@<IP>"
    log "Run 'ndi-bridge-help' for available commands"
}

# Run main function
main "$@"