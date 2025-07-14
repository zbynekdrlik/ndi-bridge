# NDI Bridge

[![Version](https://img.shields.io/badge/version-1.0.7-blue.svg)](https://github.com/zbynekdrlik/ndi-bridge/releases)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Overview

NDI Bridge is a high-performance, low-latency tool that bridges video capture devices to NDI (Network Device Interface) streams. It supports multiple capture sources including consumer webcams, HDMI capture devices, and professional broadcast equipment.

## Features

### Current Features (v1.0.7)
- ✅ **Media Foundation** capture support (Windows)
- ✅ **Interactive device selection** with numbered menu
- ✅ **Command-line interface** with positional parameters
- ✅ **Automatic device reconnection** on disconnect
- ✅ **Real-time format conversion** to NDI-compatible formats
- ✅ **Frame statistics** and performance monitoring
- ✅ **Configurable retry logic** for resilient operation

### In Development (v1.1.0)
- 🔄 **DeckLink** capture support (Blackmagic devices)
- 🔄 **Multi-capture** type selection
- 🔄 **Professional broadcast** features

### Planned Features
- 📋 **Linux V4L2** support
- 📋 **Audio capture** and synchronization
- 📋 **Configuration files** for saved setups
- 📋 **Web UI** for remote control

## Quick Start

### Prerequisites
- Windows 10/11 (Linux support coming)
- [NDI SDK 5.0+](https://ndi.tv/sdk/)
- Visual Studio 2019+ or MinGW-w64
- CMake 3.16+

### Building

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

### Basic Usage

```bash
# Interactive mode (shows device menu)
ndi-bridge.exe

# Direct mode with device and stream name
ndi-bridge.exe "Integrated Camera" "My NDI Stream"

# Using named parameters
ndi-bridge.exe -d "USB Capture" -n "Conference Room"

# List available devices
ndi-bridge.exe --list-devices
```

## Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-d, --device <name>` | Capture device name | Interactive selection |
| `-n, --ndi-name <name>` | NDI stream name | "NDI Bridge" |
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
- **Format Converter** - Efficient color space conversion
- **App Controller** - Orchestrates capture and streaming
- **NDI Sender** - Handles NDI protocol and network transmission

## Supported Capture Devices

### Media Foundation (Windows)
- USB webcams
- HDMI capture devices (Elgato, Magewell, etc.)
- Virtual cameras
- DirectShow compatible devices

### DeckLink (Coming in v1.1.0)
- Blackmagic DeckLink cards
- UltraStudio devices
- Professional SDI/HDMI interfaces

## Performance

- **Latency**: < 1 frame (typically 16-33ms)
- **CPU Usage**: ~5-15% (depends on resolution)
- **Memory**: ~100-200MB
- **Network**: 100-200 Mbps (1080p60)

## Troubleshooting

### No devices found
- Ensure capture device is connected
- Check Windows Device Manager
- Try running as Administrator
- Update device drivers

### NDI stream not visible
- Check firewall settings
- Ensure NDI Tools are installed
- Verify network connectivity
- Use NDI Studio Monitor to test

### High CPU usage
- Use hardware-accelerated capture devices
- Lower capture resolution
- Ensure Release build is used

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
- Contributors and testers

## Support

- **Issues**: [GitHub Issues](https://github.com/zbynekdrlik/ndi-bridge/issues)
- **Discussions**: [GitHub Discussions](https://github.com/zbynekdrlik/ndi-bridge/discussions)
- **Email**: zbynek.drlik@gmail.com
