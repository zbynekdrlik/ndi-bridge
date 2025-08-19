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

```bash
# CORRECT: Create bootable USB image with output redirection
sudo ./build-image-for-rufus.sh > build-rufus.log 2>&1 &
# Monitor progress in separate terminal or with:
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
