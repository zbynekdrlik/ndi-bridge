# NDI Bridge

[![Version](https://img.shields.io/badge/version-2.1.6-blue.svg)](https://github.com/zbynekdrlik/ndi-bridge/releases)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

NDI Bridge is a high-performance, ultra-low-latency tool that bridges video capture devices to NDI (Network Device Interface) streams. It enables seamless integration of HDMI capture cards, webcams, and professional video equipment into IP-based video workflows.

## 🚀 Latest Updates (v2.1.6)

- **Fixed Boot Issues**: USB systems now boot properly with correct partition layout
- **Fixed TTY2 Display**: Welcome screen shows with proper colors and auto-refresh
- **USB Hot-plug Recovery**: Automatic recovery when USB capture devices are disconnected/reconnected
- **Bootable USB Appliance**: Ready-to-deploy Linux system with auto-starting NDI Bridge
- **Improved Stability**: Enhanced error handling and frame monitoring
- **Network Bridge**: Dual ethernet port support for daisy-chaining devices

## Features

### Current Features (v2.1.6)
- ✅ **USB Hot-plug Recovery** - Automatically restarts when devices disconnect/reconnect
- ✅ **Bootable USB System** - Complete Linux appliance for dedicated NDI Bridge boxes
- ✅ **Ultra-low latency pipeline** with multi-threading (Linux)
- ✅ **Media Foundation** capture support (Windows)
- ✅ **DeckLink** capture support with extreme latency optimization (Windows)
- ✅ **V4L2** capture support with zero-copy optimization (Linux)
- ✅ **AVX2 SIMD Optimizations** for format conversion
- ✅ **Multi-threaded pipeline** with CPU core affinity (Linux)
- ✅ **Lock-free frame queues** for thread communication
- ✅ **Zero-copy format support**: YUYV, UYVY, BGRA
- ✅ **Automatic device reconnection** with frame monitoring
- ✅ **Network bridge configuration** for dual ethernet ports
- ✅ **Web-based monitoring** (TTY console interface)
- ✅ **Remote management** via SSH

### USB Appliance Features
- ✅ Read-only root filesystem (power failure safe)
- ✅ Automatic NDI Bridge startup
- ✅ Network bridge for daisy-chaining
- ✅ TTY1: Live NDI logs display
- ✅ TTY2: System status with build timestamp display
- ✅ Helper commands for management
- ✅ 0-second boot time (GRUB timeout)
- ✅ Power button disabled (always-on operation)
- ✅ High-precision time synchronization (PTP/NTP) for optimal NDI frame sync
- ✅ **mDNS/Avahi hostname resolution** - Access via `<name>.local` addresses
- ✅ **NDI service advertisement** - Automatic NDI discovery via mDNS
- ✅ **Build timestamp tracking** - Shows when each USB image was created

## Quick Start

### Option 1: Build from Source

#### Prerequisites

**Windows**
- Windows 10/11
- [NDI SDK 5.0+](https://ndi.tv/sdk/) (NDI 6 SDK recommended)
- Visual Studio 2019+ or MinGW-w64
- CMake 3.16+
- [Blackmagic DeckLink SDK](https://www.blackmagicdesign.com/support) (optional)

**Linux**
- Ubuntu 20.04+ or equivalent
- [NDI SDK for Linux](https://ndi.tv/sdk/)
- GCC 9+ or Clang 10+
- CMake 3.16+
- V4L2 development files

#### Building

```bash
# Clone repository
git clone https://github.com/zbynekdrlik/ndi-bridge.git
cd ndi-bridge

# Create build directory
mkdir build && cd build

# Configure
cmake -DCMAKE_BUILD_TYPE=Release ..

# Build
cmake --build . --config Release   # Windows
make -j$(nproc)                    # Linux
```

### Option 2: Create Bootable USB Appliance (Recommended)

```bash
# On Ubuntu 22.04 or newer
cd ndi-bridge

# Build the binary first
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
cd ..

# Create bootable USB (requires root, with automatic logging)
sudo ./build-usb-with-log.sh /dev/sdX  # Replace sdX with your USB device
```

This creates a complete NDI Bridge appliance that:
- Boots directly into NDI Bridge
- Auto-detects and uses the first video capture device
- Provides network access via DHCP
- Shows live logs on console

## Usage

### Command Line

```bash
# Interactive device selection
./ndi-bridge

# Direct device specification
./ndi-bridge /dev/video0 "Camera 1"          # Linux
ndi-bridge.exe "USB Video Device" "Camera 1" # Windows

# With parameters
./ndi-bridge -d /dev/video0 -n "Studio Camera" -v
```

### USB Appliance

1. Boot from the USB drive
2. Connect video capture device
3. Connect network cable (either ethernet port)
4. System automatically:
   - Gets IP via DHCP
   - Starts streaming as "ndi-bridge" (or custom name)
   - Shows logs on TTY1 (Alt+F1)
   - Shows status on TTY2 (Alt+F2)

#### Default Credentials
- Username: `root`
- Password: `newlevel`

#### Helper Commands
- `ndi-bridge-info` - Display system status
- `ndi-bridge-set-name <name>` - Set device/stream name and mDNS aliases
- `ndi-bridge-logs` - View service logs
- `ndi-bridge-netstat` - Network bridge status
- `ndi-bridge-help` - Show all commands

#### mDNS Network Access
Devices are accessible via mDNS/Avahi with automatic hostname resolution:

```bash
# Set device name (on the appliance)
sudo ndi-bridge-set-name cam1

# Access from any computer on the network
ping ndi-bridge-cam1.local  # Full hostname
ping cam1.local             # Short alias (convenience)

# Future web interface will be available at:
http://cam1.local           # Port 80
```

NDI services are also advertised via mDNS for automatic discovery by NDI applications.

## Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-t, --type <type>` | Capture type: `mf`, `dl`, `v4l2` | Auto-detect |
| `-d, --device <path>` | Device path or name | Interactive |
| `-n, --ndi-name <name>` | NDI stream name | Hostname |
| `-v, --verbose` | Enable verbose logging | Disabled |
| `--version` | Show version | - |
| `-h, --help` | Show help | - |

## Network Configuration

The USB appliance creates a network bridge (br0) combining both ethernet ports:
- Either port can be used for network connection
- Second port can daisy-chain to another device
- DHCP client on bridge interface
- Avahi/mDNS for discovery

## Building USB Systems

### Quick Build
```bash
sudo ./scripts/build-ndi-usb-modular.sh /dev/sdb
```

### Build System Features
- Modular build scripts in `scripts/build-modules/`
- Helper scripts in `scripts/helper-scripts/`
- Version tracking (currently v1.2.3)
- Comprehensive logging to `build-logs/`
- ~10-15 minute build time

### Customization
Edit variables in `scripts/build-modules/00-variables.sh`:
- `ROOT_PASSWORD` - Default root password
- `DEFAULT_HOSTNAME` - Default hostname
- `UBUNTU_VERSION` - Ubuntu release to use

## Performance

### Linux V4L2 (v2.1.6)
- **Latency**: < 1ms capture to NDI
- **Zero-copy**: YUYV/UYVY direct to NDI
- **CPU Usage**: < 15% on modern CPUs
- **Reliability**: Automatic USB recovery
- **USB Boot**: Fixed boot and TTY display issues

### Windows DeckLink (v1.6.5)
- **Latency**: ~40-50ms reduction vs standard
- **Zero-copy**: 100% for UYVY/BGRA
- **Frame drops**: 0%

## Troubleshooting

### USB Device Not Found
- Check `ls -la /dev/video*`
- Verify USB connection
- Check `dmesg` for errors
- Try different USB port

### No Network Connection
- Check cable connection
- Verify DHCP server available
- Check `ip addr show br0`
- Try static IP if needed

### Stream Not Visible
- Verify network connectivity
- Check firewall settings
- Ensure same subnet as NDI clients
- Check stream name in NDI tools

### USB Recovery Issues
If device doesn't recover after reconnect:
- Check system logs: `journalctl -u ndi-bridge`
- Manually restart: `systemctl restart ndi-bridge`
- Verify USB power management settings

## Development

### Repository Structure
```
ndi-bridge/
├── src/                    # Source code
│   ├── common/            # Shared components
│   ├── windows/           # Windows-specific
│   └── linux/             # Linux-specific
├── scripts/               # Build and utility scripts
│   ├── build-modules/     # Modular USB build system
│   └── helper-scripts/    # System management tools
├── build/                 # Build output (git-ignored)
└── docs/                  # Documentation
```

### Key Components
- `AppController` - Main application logic
- `V4L2Capture` - Linux video capture
- `MediaFoundation` - Windows capture
- `DeckLinkCapture` - Professional capture
- `NDISender` - NDI transmission

### Recent Changes (v2.1.6)
- Fixed USB boot issues - systems now boot properly
- Fixed TTY2 welcome screen with color support
- Fixed partition layout and GRUB installation
- Improved build script with proper heredoc escaping
- Cleaned up obsolete documentation
- Maintained USB hot-plug recovery and all v2.1.5 features

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/name`)
3. Commit changes (`git commit -am 'Add feature'`)
4. Push branch (`git push origin feature/name`)
5. Open Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- Open an [issue](https://github.com/zbynekdrlik/ndi-bridge/issues)
- Include logs with `-v` flag
- Specify OS and device details
- Check existing issues first

## Acknowledgments

- NewTek/Vizrt for NDI SDK
- Blackmagic Design for DeckLink SDK
- V4L2 community
- All contributors and testers
