# NDI Bridge

## Overview
NDI Bridge is a high-performance, low-latency solution for bridging HDMI capture devices to NDI (Network Device Interface) streams. This multiplatform application supports both Windows and Linux environments with optimized capture methods for each platform.

## Features

### Current Features
- Low-latency HDMI to NDI streaming
- Windows support using Media Foundation API
- Blackmagic DeckLink SDK integration for professional capture cards
- Minimal resource usage for optimal performance

### Planned Features
- Linux support with bootable USB image
- Multiple simultaneous capture device support
- Real-time monitoring and diagnostics
- Configuration management
- Auto-discovery of capture devices

## Architecture

### Windows Implementation
- **Media Foundation**: For standard USB/HDMI capture devices
- **DeckLink SDK**: For Blackmagic professional capture cards
- **NDI SDK**: For network streaming output

### Linux Implementation
- **Minimalist Design**: Bootable from USB key
- **Direct Hardware Access**: For minimal latency
- **Embedded Environment**: Stripped-down Linux for dedicated operation

## Prerequisites

### Windows
- Windows 10/11
- Visual Studio 2019 or later
- NDI SDK 5.x or later
- Media Foundation (included in Windows SDK)
- DeckLink SDK (for Blackmagic devices)

### Linux
- GCC 9+ or Clang 10+
- NDI SDK for Linux
- V4L2 development libraries

## Building

### Windows
```bash
# Clone the repository
git clone https://github.com/zbynekdrlik/ndi-bridge.git
cd ndi-bridge

# Build using CMake
mkdir build
cd build
cmake .. -G "Visual Studio 16 2019" -A x64
cmake --build . --config Release
```

### Linux
```bash
# Clone the repository
git clone https://github.com/zbynekdrlik/ndi-bridge.git
cd ndi-bridge

# Build using CMake
mkdir build
cd build
cmake ..
make -j$(nproc)
```

## Usage

### Windows
```bash
ndi-bridge.exe --device "Capture Device Name" --ndi-name "NDI Source Name"
```

### Linux (Bootable USB)
1. Create bootable USB using provided scripts
2. Boot target machine from USB
3. Bridge automatically starts with detected capture device

## Configuration

Configuration can be done via:
- Command-line arguments
- Configuration file (ndi-bridge.conf)
- Environment variables

## Project Structure
```
ndi-bridge/
├── src/                    # Source code
│   ├── common/            # Shared code between platforms
│   ├── windows/           # Windows-specific implementation
│   └── linux/             # Linux-specific implementation
├── include/               # Header files
├── deps/                  # External dependencies
│   ├── ndi/              # NDI SDK
│   ├── decklink/         # DeckLink SDK
│   └── ...
├── build/                 # Build output (generated)
├── docs/                  # Documentation
├── scripts/              # Build and utility scripts
└── tests/                # Unit and integration tests
```

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues, questions, or contributions, please use the GitHub issue tracker.

## Acknowledgments

- NewTek/Vizrt for the NDI SDK
- Blackmagic Design for the DeckLink SDK
- Contributors and testers from the broadcasting community
