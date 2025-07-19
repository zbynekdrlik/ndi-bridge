#!/bin/bash
# NDI-Bridge USB Linux Builder
# Creates a complete bootable USB Linux system with NDI-Bridge
# Power failure resistant, auto-starting NDI video bridge

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
    parted -s $USB_DEVICE mklabel gpt
    
    # Create EFI partition (512MB)
    parted -s $USB_DEVICE mkpart primary fat32 1MiB 513MiB
    parted -s $USB_DEVICE set 1 esp on
    
    # Create root partition (rest of disk)
    parted -s $USB_DEVICE mkpart primary ext4 513MiB 100%
    
    # Wait for partitions to appear
    sleep 2
    partprobe $USB_DEVICE
    sleep 2
    
    # Format partitions
    log "Formatting partitions..."
    mkfs.vfat -F32 -n EFI ${USB_DEVICE}1
    mkfs.ext4 -L NDIBRIDGE ${USB_DEVICE}2
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
    log "Installing Ubuntu 22.04 base system..."
    debootstrap --arch=amd64 jammy /mnt/usb http://archive.ubuntu.com/ubuntu/
}

# Configure system
configure_system() {
    log "Configuring system..."
    
    # Create setup script
    cat > /mnt/usb/tmp/setup.sh << 'EOF'
#!/bin/bash
set -e

echo "=== Configuring NDI Bridge USB System ==="

# Update and install packages
apt-get update
apt-get install -y --no-install-recommends \
    linux-image-generic \
    grub-efi-amd64 \
    systemd \
    systemd-sysv \
    udev \
    iproute2 \
    isc-dhcp-client \
    openssh-server \
    sudo \
    nano \
    wget \
    ca-certificates \
    initramfs-tools \
    iputils-ping \
    libavahi-common3 \
    libavahi-client3 \
    v4l-utils

# Set hostname
echo "ndi-bridge" > /etc/hostname
cat > /etc/hosts << EOFHOSTS
127.0.0.1 localhost
127.0.1.1 ndi-bridge
EOFHOSTS

# Set root password
echo "root:NewLevel123!" | chpasswd

# Configure network for DHCP
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-dhcp.network << EOFNET
[Match]
Name=en*
Name=eth*

[Network]
DHCP=yes
EOFNET

systemctl enable systemd-networkd
systemctl enable systemd-resolved

# Configure SSH
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable ssh

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
    LD_LIBRARY_PATH=/usr/local/lib /opt/ndi-bridge/ndi-bridge "$DEVICE" "$NDI_NAME" 2>&1 | tee -a /var/log/ndi-bridge/ndi-bridge.log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] NDI Bridge exited, restarting in 5 seconds..." | tee -a /var/log/ndi-bridge/ndi-bridge.log
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
cat > /etc/systemd/system/setup-logs.service << EOFSETUP
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
EOFSETUP

systemctl enable setup-logs

# Configure auto-login on TTY1 to show ndi-bridge output
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << EOFGETTY
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
Type=idle
EOFGETTY

# Create profile script to show ndi-bridge logs on console
cat > /root/.profile << EOFPROFILE
# Show NDI Bridge status on login
clear
echo "=== NDI Bridge System ==="
echo "IP: \$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)"
echo ""
echo "Following NDI Bridge logs (Ctrl+C to exit to shell)..."
echo ""
journalctl -u ndi-bridge -f --no-pager
EOFPROFILE

# NDI name updater (handles read-only filesystem)
cat > /usr/local/bin/set-ndi-name << 'EOFNAME'
#!/bin/bash
if [ $# -eq 0 ]; then
    echo "Usage: set-ndi-name <name>"
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
chmod +x /usr/local/bin/set-ndi-name

# Helper to remount filesystem
cat > /usr/local/bin/rw << 'EOFRW'
#!/bin/bash
mount -o remount,rw /
echo "Filesystem mounted read-write. Use 'ro' to return to read-only."
EOFRW
chmod +x /usr/local/bin/rw

cat > /usr/local/bin/ro << 'EOFRO'
#!/bin/bash
sync
mount -o remount,ro /
echo "Filesystem mounted read-only."
EOFRO
chmod +x /usr/local/bin/ro

# Configure GRUB with 2 second timeout for fast boot
cat > /etc/default/grub << EOFGRUB
GRUB_DEFAULT=0
GRUB_TIMEOUT=2
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="NDI Bridge Linux"
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX=""
EOFGRUB

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=NDIBRIDGE --removable
update-grub

# Create fstab
UUID_ROOT=$(blkid -s UUID -o value /dev/sdb2)
UUID_EFI=$(blkid -s UUID -o value /dev/sdb1)
cat > /etc/fstab << EOFFSTAB
UUID=$UUID_ROOT / ext4 ro,noatime,errors=remount-ro 0 1
UUID=$UUID_EFI /boot/efi vfat umask=0077 0 1
EOFFSTAB

# Configure ldconfig for NDI
echo "/usr/local/lib" > /etc/ld.so.conf.d/ndi.conf
ldconfig

# Configure power failure resistance
# Set filesystem to journal data mode
tune2fs -o journal_data /dev/sdb2

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
EOF

    chmod +x /mnt/usb/tmp/setup.sh
}

# Copy NDI files
copy_ndi_files() {
    log "Copying NDI files..."
    
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
    log "Running setup in chroot..."
    
    # Mount necessary filesystems
    mount --bind /dev /mnt/usb/dev
    mount --bind /proc /mnt/usb/proc
    mount --bind /sys /mnt/usb/sys
    
    # Run setup script
    chroot /mnt/usb /tmp/setup.sh
    
    # Unmount
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
    log "Starting NDI-Bridge USB Linux Builder"
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
}

# Run main function
main "$@"