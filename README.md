# NDI Bridge

[![Version](https://img.shields.io/badge/version-1.3.1-blue.svg)](https://github.com/zbynekdrlik/ndi-bridge/releases)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

NDI Bridge is a high-performance, low-latency tool that bridges video capture devices to NDI (Network Device Interface) streams. It enables seamless integration of HDMI capture cards, webcams, and professional video equipment into IP-based video workflows.

## Features

### Current Features (v1.3.1)
- ✅ **Media Foundation** capture support (Windows)
- ✅ **DeckLink** capture support (Blackmagic devices - Windows)
- ✅ **V4L2** capture support (Linux USB devices)
- ✅ **AVX2 Optimizations** for Intel N100 and compatible processors
- ✅ **Multi-capture type selection** (Windows: `-t mf` or `-t dl`, Linux: `-t v4l2`)
- ✅ **Cross-platform support** (Windows and Linux)
- ✅ **Interactive device selection** with numbered menu
- ✅ **Command-line interface** with positional parameters
- ✅ **Automatic device reconnection** on disconnect
- ✅ **Professional streaming features**:
  - Ultra-low latency (< 1 frame delay)
  - Hardware-accelerated capture
  - Zero-copy frame handling
  - Real-time format conversion
  - Automatic format detection
- ✅ **Robust error handling** with descriptive messages
- ✅ **Comprehensive logging** with timestamps
- ✅ **Refactored DeckLink architecture** for better maintainability
- ✅ **Media Foundation proper shutdown** to prevent device issues
- ✅ **Clean logging system** with consistent timestamp format
- ✅ **V4L2 format conversion** (YUYV, UYVY, NV12, RGB24, BGR24 to BGRA)
- ✅ **SIMD-optimized YUV conversion** with AVX2 (3x faster)

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
- AVX2-capable CPU for optimizations (Intel N100 or newer)

### Building

#### Windows
```bash
# Clone repository
git clone https://github.com/zbynekdrlik/ndi-bridge.git
cd ndi-bridge

# Create build directory
mkdir build && cd build

# Configure
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

# Configure (AVX2 enabled by default for Intel N100)
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

# Direct mode with device name
ndi-bridge.exe "USB Video Device" "My NDI Stream"

# Using command-line options
ndi-bridge.exe -t mf -d "Elgato HD60" -n "Gaming PC"

# DeckLink device
ndi-bridge.exe -t dl -d "DeckLink SDI" -n "Studio Camera"

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
| `-h, --help` | Show help message | - |
| `-r, --retry <sec>` | Retry interval in seconds | 5 |
| `-m, --max-retries <n>` | Maximum retry attempts (-1 = infinite) | -1 |

## Architecture

NDI Bridge uses a modular architecture with clear separation of concerns:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Capture   │────▶│   Format     │────▶│    NDI      │
│   Device    │     │  Converter   │     │   Sender    │
└─────────────┘     └──────────────┘     └─────────────┘
       │                                          │
       └──────────────┐      ┌───────────────────┘
                      ▼      ▼
                 ┌──────────────┐
                 │     App      │
                 │  Controller  │
                 └──────────────┘
```

### Key Components

- **Capture Interface** - Unified API for all capture devices
- **Format Converter** - Efficient color space conversion (UYVY, BGRA, YUV420, NV12, YUYV)
- **App Controller** - Orchestrates capture and streaming
- **NDI Sender** - Handles NDI protocol and network transmission
- **Device Enumerator** - Device discovery and management
- **Logger** - Thread-safe logging with timestamps

## Supported Devices

### Media Foundation (Windows)
- USB webcams
- USB HDMI capture cards (Elgato, AVerMedia, etc.)
- NZXT Signal HD60
- DirectShow compatible devices

### DeckLink (Windows)
- All Blackmagic DeckLink cards
- DeckLink Mini series
- DeckLink SDI series
- DeckLink Studio series
- Automatic format detection
- No-signal handling

### V4L2 (Linux)
- USB webcams
- USB HDMI capture devices (NZXT, Elgato, etc.)
- V4L2 compatible devices
- Format support: YUYV, UYVY, NV12, RGB24, BGR24
- Automatic format detection and conversion
- AVX2-optimized conversion on supported CPUs

## Performance

- **Latency**: < 1 frame (typically 16-33ms)
- **CPU Usage**: < 10% for 1080p60 (Intel N100 with AVX2)
- **Memory**: < 200MB typical
- **Network**: 100-150 Mbps for 1080p60
- **Format Conversion**: < 5ms per frame with AVX2

### Intel N100 Optimizations
- AVX2 SIMD instructions for YUV→BGRA conversion
- Processes 16 pixels simultaneously
- ~70% reduction in conversion CPU usage
- Optimized for E-core architecture
- Runtime CPU feature detection

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
- Enable AVX2 in CMake (Linux)
- Ensure Release build is used
- Lower capture resolution
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
- Verify AVX2 support: `lscpu | grep avx2`

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- NewTek/Vizrt for the NDI SDK
- Blackmagic Design for DeckLink SDK
- V4L2 community for Linux video support
- Intel for AVX2 technology
- Contributors and testers

## Support

For issues, questions, or contributions:
- Open an issue on [GitHub](https://github.com/zbynekdrlik/ndi-bridge/issues)
- Check existing issues for solutions
- Include logs with `-v` flag when reporting issues
