# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important Build Guidelines

### Version Management
- **⚠️ MANDATORY: Before EVERY `build-image-for-rufus.sh` run, you MUST increment BUILD_SCRIPT_VERSION** in `scripts/build-modules/00-variables.sh`
- This version appears on the second console (tty2) of the NDI Bridge box, allowing identification of which image version is deployed
- The build timestamp is automatically generated and displayed alongside the version on the console
- **Why this matters:** Without incrementing the version, you cannot distinguish between different builds on deployed devices
- Format: Major.Minor.Patch (e.g., 1.5.0)
  - Major: Breaking changes to the build system
  - Minor: New features or significant improvements  
  - Patch: Bug fixes and minor adjustments
- **The version and build date are shown on tty2 console of the physical NDI Bridge box**

## Quick Environment Setup

**ALWAYS run this first on a new machine:**
```bash
./setup-build-environment.sh
```

This script automatically:
- Detects system type (Linux/WSL)  
- Installs all build dependencies
- Downloads and installs NDI SDK v6.2.0
- Installs USB creation tools
- Verifies the complete build environment
- Tests compilation

## Build Commands

### Standard Build (Release)
```bash
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)  # Linux
cmake --build . --config Release  # Windows
```

### Debug Build
```bash
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Debug ..
make -j$(nproc)  # Linux
cmake --build . --config Debug  # Windows
```

### USB Appliance Build (Linux/WSL)

**⚠️ CRITICAL: Build Script Output Handling**
- **NEVER run `build-image-for-rufus.sh` with direct console output** - it causes Claude to crash due to excessive binary dump output
- **ALWAYS redirect output to a file and monitor the file separately**
- The script produces large amounts of binary data that must not be displayed directly
- **Script location**: The script is in the repository root directory, NOT in scripts/

```bash
# CORRECT: Create bootable USB image with output redirection (run from repo root)
cd /mnt/c/Users/newlevel/Documents/GitHub/ndi-bridge
sudo ./build-image-for-rufus.sh 2>&1 | tee build-logs/build.log | grep -E "(Step|Progress|Error|Warning|Complete|Building|Creating|Installing)"

# Alternative: Run in background and monitor
sudo ./build-image-for-rufus.sh > build-rufus.log 2>&1 &
tail -f build-rufus.log | grep -E "(Step|Progress|Error|Warning|Complete)"

# OR: Direct USB creation (native Linux) - also redirect output
sudo ./build-usb-with-log.sh /dev/sdX > build-usb.log 2>&1  # Replace sdX with USB device
```

**Monitoring Build Progress:**
- Use `tail -f` with grep filters to track specific events
- Check file size periodically: `ls -lh *.img`
- Monitor system resources: `htop` or `top` to ensure build is running
- Expected build time: 10-20 minutes depending on system

### Build Options
- `BUILD_TESTS=ON/OFF` - Build unit tests (default: OFF)
- `USE_DECKLINK=ON/OFF` - Enable DeckLink support on Windows (default: ON)
- `MF_SYNCHRONOUS_MODE=ON/OFF` - Experimental synchronous capture mode (default: OFF)
- `NDI_SDK_DIR=/path` - Custom NDI SDK location

## Running and Testing

### Basic Usage
```bash
# Interactive device selection
./ndi-bridge

# Specify device and NDI name
./ndi-bridge /dev/video0 "Camera 1"          # Linux
ndi-bridge.exe "USB Video Device" "Camera 1" # Windows
```

### USB Appliance Helper Commands
- `ndi-bridge-info` - System status and device information
- `ndi-bridge-logs` - View service logs  
- `ndi-bridge-set-name <name>` - Set NDI stream name
- `ndi-bridge-netstat` - Network bridge status
- `ndi-bridge-web` - Web interface control (status, restart, password management)

## Architecture Overview

### Core Components

**AppController** (`src/common/app_controller.h`)
- Main application coordinator managing lifecycle
- Handles initialization, error recovery, and shutdown
- Coordinates between capture devices and NDI sender
- Provides retry logic and statistics tracking

**ICaptureDevice Interface** (`src/capture/ICaptureDevice.h`, `src/common/capture_interface.h`)
- Abstract interface for all capture implementations
- Two versions exist due to refactoring - newer code uses `src/capture/`
- Defines frame callbacks, device enumeration, and error handling

**NDI Sender** (`src/common/ndi_sender.h`)
- Manages NDI stream transmission
- Handles format conversion and frame timing
- Provides connection statistics

### Platform-Specific Capture Implementations

**Linux V4L2** (`src/linux/v4l2/`)
- `v4l2_capture.cpp` - Main V4L2 capture implementation
- `v4l2_format_converter.cpp` - CPU-based format conversion
- `v4l2_format_converter_avx2.cpp` - SIMD-optimized conversions
- Zero-copy pipeline for YUYV/UYVY formats
- USB hot-plug recovery support

**Windows Media Foundation** (`src/windows/media_foundation/`)
- Modern Windows capture API implementation
- Supports webcams and USB capture devices
- Includes error handling and format management

**Windows DeckLink** (`src/capture/DeckLinkCaptureDevice.h`)
- Professional capture card support via Blackmagic SDK
- Ultra-low latency optimizations
- Modular design with separate components for callbacks, statistics, format management

### Support Infrastructure

**Thread Pool** (`src/common/pipeline_thread_pool.h`)
- CPU core affinity management for Linux
- High-performance pipeline threading

**Frame Queue** (`src/common/frame_queue.h`)
- Lock-free frame buffering between capture and NDI
- Prevents frame drops during processing

**Logger** (`src/common/logger.h`)
- Centralized logging with verbosity levels
- Version logging and startup information

## Testing and Network Connectivity

### mDNS/Bonjour Testing in WSL
**⚠️ IMPORTANT: mDNS (*.local) addresses do NOT work in WSL**
- `ping hostname.local` will fail in WSL due to mDNS resolver limitations
- **Alternative testing methods for mDNS functionality:**
  1. Ask the user to test from Windows host: `ping hostname.local`
  2. Use direct IP address: Get IP with `ip addr show br0` on the NDI Bridge box
  3. Use `avahi-browse -a -t` on another Linux machine to verify mDNS advertisements
  4. Check NDI Studio Monitor on Windows to verify NDI device discovery
  5. Use SSH with IP address instead of mDNS name when testing from WSL

### Network Testing Commands
```bash
# From WSL - use IP addresses
sshpass -p 'newlevel' ssh root@10.77.9.XXX "command"

# Ask user to test from Windows PowerShell/CMD:
# ping ndi-bridge.local
# ping shortname.local

# Verify mDNS is working on the box itself:
ssh root@IP "avahi-browse -a -t | grep -i ndi"
ssh root@IP "systemctl status avahi-daemon"
```

## USB Appliance System

The project includes a complete bootable USB build system that creates a dedicated NDI Bridge appliance:

### Build Scripts (`scripts/build-modules/`)
Modular build system with numbered scripts:
- `00-variables.sh` - Configuration variables (hostname, passwords, versions)
- `01-functions.sh` - Shared utility functions
- `02-prerequisites.sh` - Install build dependencies
- `03-partition.sh` - Create USB partition layout
- `04-mount.sh` - Mount filesystem
- `05-debootstrap.sh` - Bootstrap Ubuntu base system
- `06-system-config.sh` - Configure system settings
- `07-base-setup.sh` - Install base packages
- `08-network.sh` - Configure network bridge (dual ethernet)
- `09-ndi-service.sh` - Install NDI Bridge as systemd service
- `10-tty-config.sh` - Configure console displays
- `11-filesystem.sh` - Final filesystem setup
- `12-helper-scripts.sh` - Install management tools
- `12-time-sync.sh` - High-precision time synchronization (PTP/NTP)
- `13-helper-scripts-inline.sh` - Embed script contents
- `14-power-resistance.sh` - Power failure protection

### Helper Scripts (`scripts/helper-scripts/`)
Management tools for USB appliance:
- Read-only filesystem with writable overlays
- Live log monitoring and system status
- Network configuration and device naming
- Auto-recovery and hot-plug support

## Version and Platform Information

- Current version defined in `src/common/version.h`
- Cross-platform C++17 codebase
- NDI SDK 5.0+ support (NDI 6 compatible)
- USB appliance based on Ubuntu with read-only root filesystem

## Development Notes

### Format Handling
- Zero-copy path for YUYV/UYVY formats (Linux)
- AVX2 SIMD optimizations for format conversion
- NDI-native format support when possible

### Error Recovery
- Automatic USB device reconnection (Linux)
- Configurable retry logic in AppController
- Frame monitoring and pipeline restart

### Performance Optimization
- CPU core affinity (Linux)
- Lock-free frame queues
- Multi-threaded pipeline architecture
- Direct V4L2 buffer mapping (Linux)

### Time Synchronization
- PTP (Precision Time Protocol) support for sub-microsecond accuracy
- NTP fallback for general network time sync  
- Critical for frame-accurate NDI streaming in professional environments

## Read-Only Filesystem and Power Resistance

### Design Philosophy
The NDI Bridge USB appliance is designed with **extreme power-outage resistance** as a primary goal:
- **Read-only root filesystem** prevents corruption during unexpected power loss
- **tmpfs overlays** provide writable areas in RAM that are lost on reboot (by design)
- **No persistent state changes** - configuration changes require explicit remount to read-write
- **Automatic recovery** - system always boots to a known good state

### Read-Only Filesystem Architecture
```
/ (root)          - Read-only ext4 filesystem
├── /tmp          - tmpfs (RAM, cleared on reboot)
├── /var/log      - tmpfs (RAM, logs lost on reboot)
├── /var/lib      - Partially tmpfs for runtime state
└── /run          - tmpfs (RAM, runtime state)
```

### Important Considerations for Development
When adding features that require file writes:
1. **Nginx**: Requires writable directories for proxy buffering
   - Solution: Create `/var/lib/nginx/*` directories after boot
   - Disable proxy buffering with `proxy_buffering off`

2. **Service configurations**: Must handle read-only filesystem
   - Solution: Create required directories in tmpfs during boot
   - Use systemd tmpfiles.d for automatic directory creation

3. **Log files**: Written to tmpfs, lost on reboot
   - This is intentional for power-outage resistance
   - Use `journalctl` for persistent system logs (stored in RAM)

4. **Configuration changes**: Require explicit remount
   - Use `ndi-bridge-rw` to temporarily mount as read-write
   - Use `ndi-bridge-ro` to return to read-only mode
   - Changes persist only when saved during read-write mode

## Web Interface

### Overview
The NDI Bridge includes a web-based management interface accessible via HTTP:
- **Authentication**: HTTP Basic Auth (username: admin, password: newlevel)
- **Terminal Access**: Full bash terminal via wetty (Node.js-based web terminal)
- **Persistent Sessions**: Uses tmux for session persistence across browser connections
- **Shared Sessions**: All browsers connect to the same tmux session

### Web Interface Components
1. **Nginx**: Reverse proxy and authentication
   - Serves static landing page
   - Proxies WebSocket connections to wetty
   - Handles HTTP Basic Authentication

2. **Wetty**: Web-based terminal emulator
   - Node.js application using xterm.js
   - Connects to tmux session wrapper
   - Supports full terminal features including Ctrl-C

3. **Tmux**: Terminal multiplexer for persistence
   - Single shared session named "ndi-bridge"
   - Maintains state across browser disconnections
   - Allows multiple browsers to view same session

### Access Methods
```bash
# Web Interface URLs
http://ndi-bridge-devicename.local/     # mDNS hostname
http://shortname.local/                  # Short alias (if configured)
http://10.77.9.xxx/                      # Direct IP address

# Terminal endpoint
http://hostname/terminal/                # Opens persistent tmux session
```

### Known Limitations
1. **ndi-bridge --version** hangs when called directly
   - Workaround: `/usr/local/bin/ndi-bridge-version` wrapper with timeout
   - The binary tries to start the full application instead of just showing version

2. **mDNS in WSL**: *.local addresses don't resolve in WSL
   - Test from Windows host or use IP addresses
   - Use `avahi-browse` to verify mDNS advertisements

### Web Interface Files
- `/etc/nginx/sites-available/ndi-bridge` - Nginx configuration
- `/etc/nginx/.htpasswd` - Authentication file
- `/usr/local/bin/ndi-bridge-tmux-session` - Tmux session wrapper
- `/usr/local/bin/ndi-bridge-web` - Web interface management script
- `/var/www/ndi-bridge/index.html` - Landing page
