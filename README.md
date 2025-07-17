# NDI Bridge

[![Version](https://img.shields.io/badge/version-1.6.5-blue.svg)](https://github.com/zbynekdrlik/ndi-bridge/releases)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

NDI Bridge is a high-performance, ultra-low-latency tool that bridges video capture devices to NDI (Network Device Interface) streams. It enables seamless integration of HDMI capture cards, webcams, and professional video equipment into IP-based video workflows.

## 🚀 Performance Highlights (v1.6.5)

- **Sub-millisecond latency**: 0.73ms average on Linux, ~40-50ms reduction on DeckLink
- **Zero-copy pipeline**: 100% direct memory access for UYVY and BGRA formats
- **Multi-threaded architecture**: Parallel capture, conversion, and transmission
- **AVX2 optimizations**: Hardware-accelerated format conversion
- **Lock-free queues**: Minimal thread contention
- **DeckLink optimization**: Direct callback mode with pre-allocated buffers

## Features

### Current Features (v1.6.5)
- ✅ **Ultra-low latency pipeline** with multi-threading (Linux)
- ✅ **Media Foundation** capture support (Windows)
- ✅ **DeckLink** capture support with extreme latency optimization (Windows)
  - Direct callback mode bypassing frame queues
  - True zero-copy for UYVY and BGRA formats
  - Pre-allocated conversion buffers
  - 100% zero-copy performance achieved
- ✅ **V4L2** capture support with zero-copy optimization (Linux)
- ✅ **AVX2 SIMD Optimizations** for format conversion
- ✅ **Multi-threaded pipeline** with CPU core affinity (Linux)
- ✅ **Lock-free frame queues** for thread communication
- ✅ **Zero-copy format support**:
  - YUYV/YUY2 with AVX2-accelerated byte swapping
  - UYVY direct to NDI (no conversion needed)
  - BGRA direct to NDI (no conversion needed)
- ✅ **Cross-platform support** (Windows and Linux)
- ✅ **Interactive device selection** with numbered menu
- ✅ **Command-line interface** with flexible parameters
- ✅ **Automatic device reconnection** on disconnect
- ✅ **Professional streaming features**:
  - Sub-millisecond latency (0.73ms on Intel N100)
  - Hardware-accelerated capture
  - Zero-copy frame handling
  - Real-time format conversion
  - Automatic format detection
- ✅ **Robust error handling** with descriptive messages
- ✅ **Comprehensive logging** with performance metrics
- ✅ **V4L2 format support**: YUYV, UYVY, NV12, RGB24, BGR24
- ✅ **Thread performance monitoring** and statistics

### Planned Features
- 📋 **Audio capture** and synchronization
- 📋 **Configuration files** for saved setups
- 📋 **Web UI** for remote control
- 📋 **Hardware timestamping** for precision sync
- 📋 **GPU acceleration** for format conversion
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
- AVX2-capable CPU for optimizations (Intel 4th gen+ or AMD Zen+)

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

# Configure (AVX2 enabled by default)
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

# Run with verbose logging to see performance metrics
./ndi-bridge -d /dev/video0 -v
```

## Command-Line Options

| Option | Description | Default |  
|--------|-------------|---------|  
| `-t, --type <type>` | Capture type: Windows: `mf` or `dl`, Linux: `v4l2` | Interactive selection |
| `-d, --device <n>` | Capture device name or path | Interactive selection |
| `-n, --ndi-name <n>` | NDI stream name | "NDI Bridge" |
| `-l, --list-devices` | List available devices and exit | - |
| `-v, --verbose` | Enable verbose logging with performance metrics | Disabled |
| `-h, --help` | Show help message | - |
| `-r, --retry <sec>` | Retry interval in seconds | 5 |
| `-m, --max-retries <n>` | Maximum retry attempts (-1 = infinite) | -1 |

## Architecture

### v1.5.0 Multi-threaded Pipeline (Linux)

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Capture    │────▶│   Convert    │────▶│    Send     │
│  Thread     │     │   Thread     │     │   Thread    │
│  (Core 1)   │     │  (Core 2)    │     │  (Core 3)   │
└─────────────┘     └──────────────┘     └─────────────┘
       │                    │                    │
       └────────────────────┴────────────────────┘
                            │
                    ┌───────────────┐
                    │  Lock-free    │
                    │    Queues     │
                    └───────────────┘
```

### Key Components

- **Multi-threaded Pipeline** - Parallel processing with CPU affinity
- **Lock-free Queues** - Zero-contention frame passing
- **Zero-copy Path** - Direct V4L2 to NDI for YUYV format
- **AVX2 Converter** - SIMD-optimized format conversion
- **Thread Pool** - Managed thread lifecycle with monitoring
- **Capture Interface** - Unified API for all capture devices
- **App Controller** - Orchestrates capture and streaming
- **NDI Sender** - Handles NDI protocol and transmission
- **Logger** - Thread-safe logging with timestamps

## Performance Metrics

### Linux (Intel N100 - v1.5.0)
- **Average Latency**: 0.73ms (capture to NDI output)
- **Thread Performance**:
  - Capture: 1.04ms average
  - Convert: 0.10ms average (AVX2 optimized)
  - Send: 0.38ms average
- **Frame Rate**: 60 FPS sustained
- **Frame Drops**: < 0.1%
- **CPU Usage**: < 15% total across 3 cores

### DeckLink (Windows - v1.6.5)
- **Latency Reduction**: ~40-50ms vs standard implementations
- **Zero-copy Performance**: 100% for UYVY and BGRA formats
- **Direct Callback**: 100% (bypasses frame queue entirely)
- **Frame Rate**: 60 FPS sustained
- **Frame Drops**: 0%

### Performance Evolution
| Version | Latency | Improvement |
|---------|---------|-------------|
| v1.0.0 | 16.068ms | Baseline |
| v1.4.0 | 7.621ms | -52% (Zero-copy) |
| v1.5.0 | 0.730ms | -95.5% (Multi-threaded) |
| v1.6.0 | ~40-50ms reduction | DeckLink optimization |
| v1.6.5 | 100% zero-copy | BGRA support added |

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
- Zero-copy for UYVY (YCbCr 422) and BGRA (RGB 444) formats

### V4L2 (Linux)
- USB webcams
- USB HDMI capture devices (NZXT, Elgato, etc.)
- V4L2 compatible devices
- Format support: YUYV, UYVY, NV12, RGB24, BGR24
- Zero-copy YUYV direct to NDI
- Multi-threaded pipeline with sub-millisecond latency

## Optimization Guide

### Linux Performance Tuning

#### CPU Affinity
The multi-threaded pipeline automatically assigns threads to CPU cores:
- Core 0: Reserved for system
- Core 1: Capture thread
- Core 2: Conversion thread
- Core 3: Send thread

#### Real-time Priority
For lowest latency, run with elevated privileges:
```bash
sudo ./ndi-bridge -d /dev/video0 -n "Low Latency Stream"
```

#### CPU Governor
Set CPU to performance mode:
```bash
sudo cpupower frequency-set -g performance
```

#### Verify AVX2 Support
```bash
lscpu | grep avx2
```

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

### Performance issues
- Verify AVX2 support with `lscpu | grep avx2`
- Check CPU frequency scaling
- Monitor with `htop` to verify thread distribution
- Review verbose logs for bottlenecks
- Ensure Release build configuration

### V4L2 specific issues (Linux)
- Check supported formats: `v4l2-ctl -d /dev/video0 --list-formats`
- Verify device capabilities: `v4l2-ctl -d /dev/video0 --all`
- Test capture: `v4l2-ctl --stream-mmap --stream-count=100`
- For YUYV devices, verify zero-copy path in logs

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
