# NDI Bridge USB Build Guide

This guide explains how to create bootable USB systems running NDI Bridge as a dedicated appliance.

## Overview

The USB build system creates a complete Ubuntu 24.04 LTS system that:
- Boots directly into NDI Bridge
- Automatically detects and uses video capture devices
- Provides network connectivity with dual ethernet bridging
- Runs without user intervention
- Recovers from power failures and USB disconnections

## Prerequisites

### Build Host Requirements
- Ubuntu 22.04 or newer (tested on 22.04 and 24.04)
- Root access (sudo)
- At least 10GB free disk space
- Internet connection for package downloads

### Target USB Requirements
- USB 3.0 drive recommended (USB 2.0 works but slower)
- Minimum 8GB capacity
- 16GB or larger recommended for logs and future updates

### Required Packages
```bash
sudo apt-get update
sudo apt-get install -y \
    debootstrap \
    parted \
    grub-efi-amd64-bin \
    grub-pc-bin \
    dosfstools \
    git \
    build-essential \
    cmake
```

## Quick Start

1. **Build NDI Capture Binary**
```bash
cd ndi-bridge
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
cd ..
```

2. **Create Bootable USB**
```bash
# Replace /dev/sdX with your USB device (use lsblk to find it)
# This wrapper script provides automatic logging
sudo ./build-usb-with-log.sh /dev/sdX

# Or run directly without logging:
# sudo ./scripts/build-ndi-usb-modular.sh /dev/sdX
```

3. **Wait for Build**
The process takes 10-15 minutes and will:
- Partition and format the USB
- Install Ubuntu 24.04 base system
- Configure all services
- Install NDI Capture and Display binaries

## Build System Architecture

### Modular Structure
The build system is organized into modules in `scripts/build-modules/`:

- `00-variables.sh` - Global configuration variables
- `01-functions.sh` - Common utility functions
- `02-prerequisites.sh` - Prerequisite checking
- `03-partition.sh` - USB partitioning
- `04-mount.sh` - Filesystem mounting
- `05-debootstrap.sh` - Base system installation
- `06-system-config.sh` - Package installation
- `07-base-setup.sh` - Basic system configuration
- `08-network.sh` - Network bridge setup
- `09-ndi-capture-service.sh` - NDI Capture service
- `10-tty-config.sh` - Console configuration
- `11-filesystem.sh` - Filesystem and bootloader
- `12-helper-scripts.sh` - Helper script installation
- `13-helper-scripts-inline.sh` - Inline helper creation
- `14-power-resistance.sh` - Power failure resistance features

### Helper Scripts
Management scripts in `scripts/helper-scripts/`:
- `ndi-bridge-info` - System status display
- `ndi-bridge-set-name` - Set device/stream name
- `ndi-bridge-logs` - View service logs
- `ndi-bridge-update` - Update NDI binary
- `ndi-bridge-netstat` - Network status
- `ndi-bridge-netmon` - Bandwidth monitor
- `ndi-bridge-help` - Command help

## Customization

### Basic Settings
Edit `scripts/build-modules/00-variables.sh`:

```bash
# Default credentials
ROOT_PASSWORD="newlevel"

# Network settings
DEFAULT_HOSTNAME="ndi-bridge"

# Ubuntu version
UBUNTU_VERSION="noble"  # 24.04 LTS
```

### Network Configuration
The system creates a bridge (br0) combining all ethernet interfaces:
- DHCP client enabled by default
- Both ports can be used for connectivity
- Supports daisy-chaining devices

To use static IP, modify the network configuration in module `08-network.sh`.

### NDI Settings
Default configuration in `/etc/ndi-bridge/config`:
```bash
DEVICE="/dev/video0"    # First video device
NDI_NAME=""            # Empty = use hostname
```

## Console Layout

### TTY1 - Live Logs
- Shows real-time NDI Bridge logs
- Auto-starts on boot
- Press Ctrl+C to stop following

### TTY2 - System Menu
- Displays system information
- Shows IP address (with auto-refresh)
- Lists available commands
- Press any key for shell prompt

### TTY3-6 - Additional Terminals
- Standard login prompts
- Use for troubleshooting

## Features

### Auto-Recovery
- USB device disconnection detection
- Automatic restart after 5 seconds
- Frame monitoring for stalled capture
- Service restart on failures

### Power Failure Resistance
- Journaled ext4 filesystem
- Read-write root (can be made read-only)
- Minimal writes to USB
- Logs in tmpfs (RAM)

### Security
- SSH enabled with password auth
- Root login permitted (for maintenance)
- Power button disabled
- No automatic updates

## Building Multiple USBs

To build multiple USB drives:
```bash
# First USB (with automatic logging)
sudo ./build-usb-with-log.sh /dev/sdb

# Second USB (with automatic logging)
sudo ./build-usb-with-log.sh /dev/sdc

# Each build creates a timestamped log in build-logs/
# Monitor progress with: tail -f build-logs/usb-build-*.log
```

## Troubleshooting

### Build Failures

**Package download errors**
- Check internet connectivity
- Try different Ubuntu mirror
- Check proxy settings

**Filesystem errors**
- Ensure USB is not mounted
- Check USB health with `badblocks`
- Try different USB port

**Permission denied**
- Run with sudo
- Check USB write protection

### Runtime Issues

**No video device found**
- Check USB capture device connection
- Verify with `ls /dev/video*`
- Check `dmesg` for USB errors

**No network connectivity**
- Verify ethernet cable
- Check DHCP server
- Try both ethernet ports
- Check `ip addr show br0`

**NDI stream not visible**
- Verify network connectivity
- Check firewall/VLAN settings
- Ensure same subnet as viewers
- Check with NDI Test Pattern

### Debugging

Connect via SSH or console:
```bash
# Check service status
systemctl status ndi-capture

# View logs
journalctl -u ndi-capture -f

# Check network
ip addr show
bridge link show

# Test video device
v4l2-ctl --list-devices
```

## Version History

### Build Script Versions
- v1.3.1 - Fixed boot issues, TTY2 colors, partition layout
- v1.3.0 - Power failure resistance improvements
- v1.2.3 - Modular system with helper scripts
- v1.2.2 - TTY auto-refresh for IP
- v1.2.1 - Helper script fixes
- v1.2.0 - Modular refactoring
- v1.1.3 - Power button disable, GRUB 0s
- v1.1.2 - TTY fixes
- v1.1.1 - Network monitoring tools
- v1.1.0 - Helper scripts
- v1.0.0 - Initial USB build

### NDI Bridge Versions
- v2.1.6 - Fixed TTY2 display and boot issues
- v2.1.5 - USB hot-plug recovery
- v2.1.4 - Frame monitoring
- v2.1.0 - Error handling improvements
- v2.0.0 - Multi-threaded architecture

## Advanced Topics

### Read-Only Root
To make the system more resilient:
1. Edit `/etc/fstab` to mount root as read-only
2. Move logs to tmpfs
3. Disable unnecessary writes

### Custom Packages
Add packages in `06-system-config.sh`:
```bash
apt-get install -y your-package
```

### Network Bonding
Instead of bridging, configure bonding for redundancy in `08-network.sh`.

### Multiple Cameras
Modify `/etc/ndi-bridge/config` to specify different devices or create multiple service instances.

## Support

For issues with the USB build system:
1. Check the build log in `build-logs/`
2. Verify all prerequisites are installed
3. Try with a different USB device
4. Open an issue with full error output