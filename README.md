# NDI Bridge

[![Version](https://img.shields.io/badge/version-1.3.0-blue.svg)](https://github.com/zbynekdrlik/ndi-bridge/releases)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Overview

NDI Bridge is a high-performance, low-latency tool that bridges video capture devices to NDI (Network Device Interface) streams. It supports multiple capture sources including consumer webcams, HDMI capture devices, and professional broadcast equipment.

## Features

### Current Features (v1.3.0)
- ✅ **Media Foundation** capture support (Windows)
- ✅ **DeckLink** capture support (Blackmagic devices - Windows)
- ✅ **V4L2** capture support (Linux USB devices)
- ✅ **Multi-capture type selection** (Windows: `-t mf` or `-t dl`, Linux: `-t v4l2`)
- ✅ **Cross-platform support** (Windows and Linux)
- ✅ **Interactive device selection** with numbered menu
- ✅ **Command-line interface** with positional parameters
- ✅ **Automatic device reconnection** on disconnect
- ✅ **Real-time format conversion** to NDI-compatible formats
- ✅ **Frame statistics** and performance monitoring
- ✅ **Configurable retry logic** for resilient operation
- ✅ **Professional broadcast features** (format detection, no-signal handling)
- ✅ **Serial number tracking** for device persistence
- ✅ **Rolling FPS calculation** and monitoring
- ✅ **Dynamic frame rate matching** (NDI uses actual capture rate)
- ✅ **Live statistics display** (press Enter to view)
- ✅ **Refactored DeckLink architecture** for better maintainability
- ✅ **Media Foundation proper shutdown** to prevent device issues
- ✅ **Clean logging system** with consistent timestamp format
- ✅ **V4L2 format conversion** (YUYV, UYVY, NV12, RGB24, BGR24 to BGRA)

### Planned Features
- 📋 **Audio capture** and synchronization
- 📋 **Configuration files** for saved setups
- 📋 **Web UI** for remote control
- 📋 **MJPEG decompression** for V4L2 (requires libjpeg)
- 📋 **DeckLink support for Linux**

## Quick Start

### Prerequisites

#### Windows
- Windows 10/11
- [NDI SDK 5.0+](https://ndi.tv/sdk/) (NDI 6 SDK recommended)
- Visual Studio 2019+ or MinGW-w64
- CMake 3.16+
- [Blackmagic DeckLink SDK](https://www.blackmagicdesign.com/support) (optional, for DeckLink support)

#### Linux
- Ubuntu 20.04+ or equivalent
- [NDI SDK for Linux](https://ndi.tv/sdk/)
- GCC 9+ or Clang 10+
- CMake 3.16+
- V4L2 development files (usually included in kernel headers)

### Building

#### Windows
```bash
# Clone repository
git clone https://github.com/zbynekdrlik/ndi-bridge.git
cd ndi-bridge

# Create build directory
mkdir build && cd build

# Configure (Release mode recommended)
cmake -DCMAKE_BUILD_TYPE=Release ..

# Build
cmake --build . --config Release
```

#### Linux
```bash
# Install dependencies
sudo apt-get update
sudo apt-get install build-essential cmake git

# Clone repository
git clone https://github.com/zbynekdrlik/ndi-bridge.git
cd ndi-bridge

# Download and install NDI SDK for Linux
# Follow instructions from https://ndi.tv/sdk/
# Set NDI_SDK_DIR environment variable or install to system paths

# Create build directory
mkdir build && cd build

# Configure
cmake -DCMAKE_BUILD_TYPE=Release ..

# Build
make -j$(nproc)
```

For DeckLink support on Windows, see [DeckLink Setup Guide](docs/decklink-sdk-setup.md).

### Basic Usage

#### Windows
```bash
# Interactive mode (shows device menu)
ndi-bridge.exe

# Direct mode with device and stream name
ndi-bridge.exe "Integrated Camera" "My NDI Stream"

# Using named parameters with Media Foundation
ndi-bridge.exe -t mf -d "USB Capture" -n "Conference Room"

# Using DeckLink devices
ndi-bridge.exe -t dl -d "DeckLink Mini Recorder" -n "SDI Stream"

# List available devices
ndi-bridge.exe -t mf --list-devices  # List webcams
ndi-bridge.exe -t dl --list-devices  # List DeckLink devices
```

#### Linux
```bash
# Interactive mode
./ndi-bridge

# Direct mode with device path
./ndi-bridge /dev/video0 "My NDI Stream"

# Using named parameters
./ndi-bridge -t v4l2 -d /dev/video0 -n "USB Camera"

# Using device name search
./ndi-bridge -d "HD Webcam" -n "Conference Room"

# List available devices
./ndi-bridge --list-devices
```

## Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|  
| `-t, --type <type>` | Capture type: Windows: `mf` or `dl`, Linux: `v4l2` | Interactive selection |
| `-d, --device <n>` | Capture device name or path | Interactive selection |
| `-n, --ndi-name <n>` | NDI stream name | "NDI Bridge" |
| `-l, --list-devices` | List available devices and exit | - |
| `-v, --verbose` | Enable verbose logging | Disabled |
| `--no-retry` | Disable automatic retry on errors | Enabled |
| `--retry-delay <ms>` | Delay between retries | 5000 |
| `--max-retries <n>` | Maximum retry attempts (-1 = infinite) | -1 |
| `-h, --help` | Show help message | - |
| `--version` | Show version information | - |

## Architecture

NDI Bridge uses a modular architecture with clear separation of concerns:

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐
│   Capture   │────▶│     App      │────▶│    NDI     │
│   Device    │     │  Controller  │     │   Sender   │
└─────────────┘     └──────────────┘     └────────────┘
       │                                         │
       ▼                                         ▼
┌─────────────┐                          ┌────────────┐
│   Format    │                          │  Network   │
│  Converter  │                          │  Clients   │
└─────────────┘                          └────────────┘
```

### Key Components

- **Capture Interface** - Unified API for all capture devices
- **Format Converter** - Efficient color space conversion (UYVY, BGRA, YUV420, NV12, YUYV)
- **App Controller** - Orchestrates capture and streaming
- **NDI Sender** - Handles NDI protocol and network transmission
- **Device Enumerator** - Device discovery and management
- **Logger** - Centralized logging with timestamp format

## Supported Capture Devices

### Media Foundation (Windows)
- USB webcams
- HDMI capture devices (Elgato, Magewell, etc.)
- Virtual cameras
- DirectShow compatible devices

### DeckLink (Windows)
- Blackmagic DeckLink cards
- UltraStudio devices
- Professional SDI/HDMI interfaces
- Automatic format detection
- No-signal handling

### V4L2 (Linux)
- USB webcams
- USB HDMI capture devices (NZXT, Elgato, etc.)
- V4L2 compatible devices
- Format support: YUYV, UYVY, NV12, RGB24, BGR24
- Automatic format detection and conversion

## Performance

- **Latency**: < 1 frame (typically 16-33ms)
- **CPU Usage**: ~5-15% (depends on resolution and format)
- **Memory**: ~100-200MB
- **Network**: 100-200 Mbps (1080p60)

## Troubleshooting

### No devices found
#### Windows
- Ensure capture device is connected
- Check Windows Device Manager
- Try running as Administrator
- Update device drivers
- For DeckLink: Install Desktop Video drivers

#### Linux
- Check device permissions: `ls -la /dev/video*`
- Add user to video group: `sudo usermod -a -G video $USER`
- Verify device with: `v4l2-ctl --list-devices`
- Check dmesg for USB device detection

### NDI stream not visible
- Check firewall settings
- Ensure NDI Tools are installed
- Verify network connectivity
- Use NDI Studio Monitor to test
- On Linux, check iptables/firewall rules

### High CPU usage
- Use hardware-accelerated capture devices
- Lower capture resolution
- Ensure Release build is used
- Check format conversion efficiency
- On Linux, verify V4L2 buffer settings

### DeckLink specific issues (Windows)
- Ensure DeckLink drivers are installed
- Check DeckLink control panel
- Verify input signal is present
- Check supported video formats

### V4L2 specific issues (Linux)
- Check supported formats: `v4l2-ctl -d /dev/video0 --list-formats`
- Verify device capabilities: `v4l2-ctl -d /dev/video0 --all`
- Test with simple capture: `v4l2-ctl --stream-mmap`
- Check USB bandwidth for USB 3.0 devices

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- NewTek/Vizrt for the NDI SDK
- Blackmagic Design for DeckLink SDK
- V4L2 community for Linux video support
- Contributors and testers

## Support

- **Issues**: [GitHub Issues](https://github.com/zbynekdrlik/ndi-bridge/issues)
- **Discussions**: [GitHub Discussions](https://github.com/zbynekdrlik/ndi-bridge/discussions)
- **Email**: zbynek.drlik@gmail.com
