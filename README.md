# Media Bridge

[![Version](https://img.shields.io/badge/version-2.2.7-blue.svg)](https://github.com/zbynekdrlik/media-bridge/releases)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Media Bridge is a high-performance, ultra-low-latency tool that bridges video capture devices to NDI (Network Device Interface) streams. It enables seamless integration of HDMI capture cards, webcams, and professional video equipment into IP-based video workflows.

## 🚀 Latest Updates (v2.3.0)

- **🔒 User Mode PipeWire**: All audio services run as dedicated `mediabridge` user (not root)
- **🎯 Chrome Device Isolation**: WirePlumber policies restrict Chrome to virtual devices only
- **⚡ Realtime Audio**: Configured with rtprio 95 for 5.33ms latency (256 samples @ 48kHz)
- **📁 Secure Chrome Profile**: Moved to `/var/lib/mediabridge/chrome-profile/` with proper permissions
- **🔄 Migration Script**: Automatic migration for existing deployments
- **VDO.Ninja Intercom**: Full-duplex audio communication (see [docs/INTERCOM.md](docs/INTERCOM.md))
- **PipeWire 1.4.7**: Latest version with enhanced security features (see [docs/PIPEWIRE.md](docs/PIPEWIRE.md))
- **8GB Image Size**: Expanded to support Chrome and additional features
- **USB Hot-plug Recovery**: Automatic recovery when devices disconnect/reconnect

## Features

### Current Features (v2.3.0)
- ✅ **USB Hot-plug Recovery** - Automatically restarts when devices disconnect/reconnect
- ✅ **Bootable USB System** - Complete Linux appliance for dedicated Media Bridge boxes
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
- ✅ Btrfs filesystem with Copy-on-Write (power failure safe)
- ✅ Automatic Media Bridge startup
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
- ✅ **VDO.Ninja Intercom** - Bidirectional WebRTC audio running as mediabridge user
- ✅ **VNC Remote Access** - Monitor intercom via VNC on port 5999
- ✅ **User Mode Audio** - PipeWire runs as dedicated user with proper isolation
- ✅ **Chrome Sandboxing** - Browser restricted to virtual audio devices only
- ✅ **Realtime Scheduling** - Low-latency audio with proper resource limits

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
git clone https://github.com/zbynekdrlik/media-bridge.git
cd media-bridge

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
cd media-bridge

# Build the binary first
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
cd ..

# Create bootable USB (requires root, with automatic logging)
sudo ./build-image.sh  # Creates 8GB image file (media-bridge.img)
```

This creates a complete Media Bridge appliance that:
- Boots directly into Media Bridge
- Auto-detects and uses the first video capture device
- Provides network access via DHCP
- Shows live logs on console

## Usage

### Command Line

```bash
# Interactive device selection
./ndi-capture

# Direct device specification
./ndi-capture /dev/video0 "Camera 1"          # Linux
ndi-capture.exe "USB Video Device" "Camera 1" # Windows

# With parameters
./ndi-capture -d /dev/video0 -n "Studio Camera" -v
```

### USB Appliance

1. Boot from the USB drive
2. Connect video capture device
3. Connect network cable (either ethernet port)
4. System automatically:
   - Gets IP via DHCP
   - Starts streaming as "media-bridge" (or custom name)
   - Shows logs on TTY1 (Alt+F1)
   - Shows status on TTY2 (Alt+F2)

#### Default Credentials
- Username: `root`
- Password: `newlevel`

#### Helper Commands
- `media-bridge-info` - Display system status
- `media-bridge-set-name <name>` - Set device/stream name and mDNS aliases
- `media-bridge-logs` - View service logs
- `media-bridge-netstat` - Network bridge status
- `media-bridge-help` - Show all commands
- `vdo-ninja-intercom-logs` - View intercom logs
- `vdo-ninja-intercom-restart` - Restart intercom service
- `systemctl status vdo-ninja-intercom` - Check intercom service status

#### mDNS Network Access
Devices are accessible via mDNS/Avahi with automatic hostname resolution:

```bash
# Set device name (on the appliance)
sudo media-bridge-set-name cam1

# Access from any computer on the network
ping media-bridge-cam1.local  # Full hostname
ping cam1.local             # Short alias (convenience)

# Future web interface will be available at:
http://cam1.local           # Port 80
```

NDI services are also advertised via mDNS for automatic discovery by NDI applications.

## Security Features (NEW in v2.3.0)

### User Mode Audio Architecture
All audio services run as the dedicated `mediabridge` user (UID 999), eliminating root access to audio hardware:
- **No root audio processing**: Enhanced security posture
- **Process isolation**: mediabridge user has minimal system privileges
- **Chrome sandboxing**: Browser runs without root access
- **Realtime scheduling**: Configured via limits.conf (rtprio 95)

### Chrome Device Isolation
- **WirePlumber policies**: Restrict Chrome to virtual devices only
- **Virtual audio devices**: `intercom-speaker` and `intercom-microphone`
- **Hardware protection**: Chrome cannot access USB or HDMI audio directly
- **Secure profile**: Chrome profile in `/var/lib/mediabridge/chrome-profile/`

### Migration for Existing Systems
For deployments using the old root-based architecture:
```bash
ssh root@device
/usr/local/bin/migrate-pipewire-user.sh
sudo reboot
```

## VDO.Ninja Intercom

The Media Bridge appliance includes built-in bidirectional audio intercom functionality using VDO.Ninja WebRTC technology.

### Intercom Features
- **Secure Operation**: Runs as mediabridge user with Chrome isolation
- **Automatic Connection**: Connects to VDO.Ninja room at boot
- **USB Audio Support**: CSCTEK USB headset (0573:1573) for local audio
- **Device Isolation**: Chrome restricted to virtual audio devices
- **PipeWire 1.4.7**: Latest audio stack with security enhancements
- **VNC Monitoring**: Remote desktop access on port 5999
- **Auto-recovery**: Automatically restarts if connection drops
- **Persistent Configuration**: Settings preserved across reboots

### Intercom Configuration

The intercom connects to a VDO.Ninja room using the device hostname:
- **Room Name**: `nl_interkom` (default)
- **Device ID**: Uses hostname (e.g., `media-bridge-cam1`)
- **Audio Device**: USB Audio (3.5mm jack on device)

### Remote Access

#### VNC Access (Port 5999)
```bash
# Connect to intercom display (using mDNS hostname)
vncviewer cam1.local:5999    # No password required
vncviewer media-bridge-cam1.local:5999    # Alternative full hostname
```

#### Web Control Interface
Control the intercom settings from any browser:
```
http://cam1.local               # Device web interface
http://192.168.1.100            # Using IP address
```

Features:
- **Mic Mute**: Large button for quick mute/unmute (affects both VDO and self-monitor)
- **Others Volume**: Control volume of other participants (0-100%)
- **Self Monitor Volume**: Adjust how loud you hear yourself (0-100%)
- **Mic Gain**: Adjust microphone sensitivity if others can't hear you well
- **Save Defaults**: Save current settings to persist across reboots

#### VDO.Ninja Room View
Access the VDO.Ninja control page from any browser:
```
https://vdo.ninja/?room=nl_interkom&view
```

This shows all connected Media Bridge devices in the room.

### Troubleshooting Intercom

#### Check Service Status
```bash
ssh root@cam1.local
systemctl status media-bridge-intercom       # Main intercom service
systemctl status media-bridge-intercom-web   # Web control interface
```

#### View Logs
```bash
media-bridge-intercom-logs
# or
journalctl -u media-bridge-intercom -f
journalctl -u media-bridge-intercom-web -f   # Web interface logs
```

#### Restart Service
```bash
media-bridge-intercom-restart
# or
systemctl restart media-bridge-intercom
```

#### Audio Issues
- Ensure USB audio device is connected to 3.5mm jack
- Check PipeWire status: `systemctl status pipewire`
- Verify audio device: `pactl list sinks`

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
- Version tracking (currently v1.9.0)
- Comprehensive logging to `build-logs/`
- 8GB image size (expanded from 4GB for Chrome and intercom features)
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
- Check system logs: `journalctl -u ndi-capture`
- Manually restart: `systemctl restart ndi-capture`
- Verify USB power management settings

## Development

### Testing

For complete testing procedures and instructions, see [Testing Documentation](docs/TESTING.md).

### Repository Structure
```
media-bridge/
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

### Documentation

Key documentation files:
- [PipeWire Architecture](docs/PIPEWIRE.md) - Unified system-wide audio architecture
- [Build Instructions](docs/BUILD.md) - Detailed build process
- [Changelog](docs/CHANGELOG.md) - Version history
- [Contributing Guide](docs/CONTRIBUTING.md) - Development guidelines

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

- Open an [issue](https://github.com/zbynekdrlik/media-bridge/issues)
- Include logs with `-v` flag
- Specify OS and device details
- Check existing issues first

## Acknowledgments

- NewTek/Vizrt for NDI SDK
- Blackmagic Design for DeckLink SDK
- V4L2 community
- All contributors and testers
