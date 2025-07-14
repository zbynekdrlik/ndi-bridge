# NDI Bridge

## Overview
NDI Bridge is a high-performance, low-latency solution for bridging video capture devices to NDI (Network Device Interface) streams. This multiplatform application supports both Windows and Linux environments with optimized capture methods for each platform.

**Current Version: 1.0.3**

## Features

### Current Features
- Low-latency video capture to NDI streaming
- Windows support using Media Foundation API
- Automatic device enumeration and selection
- Robust error handling with automatic retry
- Real-time frame statistics
- Command-line interface

### Planned Features
- Linux support with V4L2
- Blackmagic DeckLink SDK integration
- Multiple simultaneous capture device support
- Real-time monitoring and diagnostics
- Configuration file support
- Web-based control interface

## Prerequisites

### Windows
- Windows 10/11
- Visual Studio 2019 or later (2022 recommended)
- CMake 3.16 or later
- **NDI SDK 5.x or 6.x** (see [NDI SDK Setup Guide](docs/ndi-sdk-setup.md))

### Linux (Planned)
- GCC 9+ or Clang 10+
- CMake 3.16 or later
- NDI SDK for Linux
- V4L2 development libraries

## NDI SDK Setup

The NDI SDK is required to build this project. See the [NDI SDK Setup Guide](docs/ndi-sdk-setup.md) for detailed instructions.

**Quick Setup (Recommended):**
1. Download NDI SDK from https://ndi.video/for-developers/ndi-sdk/
2. Extract to `deps/ndi/` in the project directory
3. Ensure the following structure:
   ```
   ndi-bridge/deps/ndi/
   ├── include/Processing.NDI.Lib.h
   └── lib/x64/
       ├── Processing.NDI.Lib.x64.lib
       └── Processing.NDI.Lib.x64.dll
   ```

## Building

### Windows (Visual Studio)
```bash
# Clone the repository
git clone https://github.com/zbynekdrlik/ndi-bridge.git
cd ndi-bridge

# Option 1: Visual Studio with CMake support
# Open the folder in Visual Studio
# Select x64-Release configuration
# Build → Build All

# Option 2: Traditional CMake
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
```

The executable will be in:
- VS CMake: `out/build/x64-Release/bin/ndi-bridge.exe`
- Traditional: `build/bin/Release/ndi-bridge.exe`

## Usage

### Basic Usage
```bash
# List available capture devices
ndi-bridge.exe --list-devices

# Start streaming with default device
ndi-bridge.exe

# Start with specific device
ndi-bridge.exe --device "USB Video Device" --ndi-name "My NDI Stream"

# Enable verbose logging
ndi-bridge.exe --verbose
```

### Command-Line Options
- `-d, --device <name>` - Capture device name (default: first available)
- `-n, --ndi-name <name>` - NDI sender name (default: 'NDI Bridge')
- `-l, --list-devices` - List available capture devices
- `-v, --verbose` - Enable verbose logging
- `--no-retry` - Disable automatic retry on errors
- `--retry-delay <ms>` - Delay between retries (default: 5000)
- `--max-retries <count>` - Maximum retry attempts (-1 for infinite)
- `-h, --help` - Show help message
- `--version` - Show version information

### Stopping the Application
Press `Enter` while the application is running to stop gracefully.

## Architecture

### Components
- **Capture Interface** - Abstract interface for video capture implementations
- **Media Foundation Capture** - Windows implementation using Media Foundation
- **NDI Sender** - Wrapper around NDI SDK for sending video frames
- **Application Controller** - Coordinates capture and sending with error recovery
- **Format Converter** - Handles video format conversions (YUY2/NV12 to UYVY)

### Error Handling
- Automatic device reinitialization on errors
- Configurable retry logic with exponential backoff
- Comprehensive error logging
- Graceful degradation

## Project Structure
```
ndi-bridge/
├── src/                    # Source code
│   ├── common/            # Platform-independent code
│   │   ├── capture_interface.h
│   │   ├── ndi_sender.cpp/h
│   │   ├── app_controller.cpp/h
│   │   └── version.h
│   ├── windows/           # Windows-specific implementation
│   │   └── media_foundation/
│   └── main.cpp          # Application entry point
├── deps/                  # External dependencies
│   └── ndi/              # NDI SDK (user-provided)
├── docs/                  # Documentation
│   ├── ndi-sdk-setup.md
│   └── development.md
├── include/              # Public headers (currently unused)
├── scripts/              # Build and utility scripts
├── tests/                # Unit tests (planned)
├── CMakeLists.txt        # Build configuration
└── README.md             # This file
```

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## Development

See [Development Guide](docs/development.md) for:
- Code style guidelines
- Architecture details
- Testing procedures
- Release process

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or contributions:
- Use the [GitHub issue tracker](https://github.com/zbynekdrlik/ndi-bridge/issues)
- Check existing issues before creating new ones
- Include version information and logs when reporting issues

## Acknowledgments

- NewTek/Vizrt for the NDI SDK
- Microsoft for Media Foundation
- Contributors and testers from the broadcasting community

## Changelog

### Version 1.0.3 (2025-01-13)
- Fixed compilation errors with Visual Studio CMake integration
- Improved callback type handling
- Fixed deprecation warnings

### Version 1.0.2 (2025-01-13)
- Fixed missing Media Foundation headers
- Corrected include paths for VS CMake

### Version 1.0.1 (2025-01-11)
- Fixed interface mismatches
- Added missing headers
- Removed unused code

### Version 1.0.0 (2025-01-11)
- Initial release with Windows support
- Media Foundation capture implementation
- NDI output functionality
- Command-line interface
