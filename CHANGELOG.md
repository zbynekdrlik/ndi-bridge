# Changelog

All notable changes to the NDI Bridge project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2025-07-15

### Added
- **Linux Support**: Full V4L2 (Video4Linux2) implementation for USB capture devices
  - V4L2 capture device implementation with memory-mapped I/O
  - Device enumeration and automatic detection
  - Support for common USB capture cards (NZXT, Elgato, etc.)
  - Format conversion for V4L2 pixel formats:
    - YUYV (YUV 4:2:2) to BGRA
    - UYVY (YUV 4:2:2) to BGRA
    - NV12 (YUV 4:2:0) to BGRA
    - RGB24 to BGRA
    - BGR24 to BGRA
  - Non-blocking capture with proper error handling
  - Thread-safe implementation

### Changed
- **Cross-Platform Build**: Updated CMake configuration for Linux support
  - Platform-specific source file selection
  - Linux-specific compiler flags
  - V4L2 dependency handling (kernel headers)
- **Main Application**: Updated to support V4L2 on Linux
  - Platform-specific capture type selection
  - Linux device enumeration
  - Unified command-line interface across platforms
- **Version System**: Updated to properly detect platform features
  - Platform-specific feature flags
  - Runtime platform detection

### Technical Details
- V4L2 implementation uses direct kernel API (no external libraries)
- Memory-mapped buffers for efficient frame capture
- ITU-R BT.601 color space conversion for YUV formats
- Automatic format negotiation with capture devices
- Support for both device paths (/dev/video0) and device name search

### Known Limitations
- MJPEG decompression not implemented (requires libjpeg)
- DeckLink support not included for Linux (Windows only)
- Focus on USB capture devices only

## [1.2.2] - 2025-07-15

### Changed
- **Simplified Logger Format**: Removed module names from log output
  - Changed from `[module_name] [timestamp] message` to `[timestamp] message`
  - Module names were not useful in compiled executables
  - Cleaner, more concise log output

### Fixed
- **Single Version Logging**: Only log version once at application startup
  - Removed redundant version logging from all components
  - Changed wording from "Script version" to "Version" (not a script)
- **Logger API Cleanup**: Removed `Logger::initialize()` method
  - No longer needed without module names
  - Simplified logger usage across all components

### Technical Details
- Removed `Logger::initialize()` calls from all components
- Removed `Logger::logVersion()` calls from all components except main.cpp
- Fixed remaining cout usage in device selection
- Updated all Media Foundation components to remove logger initialization

## [1.2.1] - 2025-07-15

### Added
- **Logger System**: Implemented centralized logging system per LLM instructions
  - Format: `[module_name] [timestamp] message`
  - Timestamps include milliseconds for precision
  - Support for multiple log levels: INFO, WARNING, ERROR, DEBUG
  - Version logging on startup using dedicated method

### Changed
- **Logging Format**: Standardized all logging throughout the application
  - Replaced all cout/cerr calls with Logger methods
  - Consistent timestamp format across all modules
  - Module name included in every log message
  - AppController version bumped to 1.0.3

### Technical Details
- Created Logger class in common/logger.h and common/logger.cpp
- Updated main.cpp and app_controller.cpp to use new logger
- Version is now logged on startup per LLM instruction requirements
- Debug logging only shown when verbose mode is enabled

## [1.2.0] - 2025-07-15

### Fixed
- **Media Foundation Device Release**: Fixed USB capture card monitor disconnection issue
  - Added proper `IMFMediaSource::Shutdown()` call before releasing
  - Added proper `IMFActivate::ShutdownObject()` call before releasing
  - These calls ensure the USB device is properly released when the app exits
  - Prevents monitor from disconnecting when using USB capture cards like NZXT Signal HD60

### Changed
- **Major Refactoring**: DeckLinkCaptureDevice.cpp split into 5 focused components
  - DeckLinkCaptureCallback: Handles IDeckLinkInputCallback implementation (~50 lines)
  - DeckLinkFrameQueue: Thread-safe frame queue management (~80 lines)
  - DeckLinkStatistics: FPS calculation and statistics tracking (~70 lines)
  - DeckLinkFormatManager: Format detection and change handling (~70 lines)
  - DeckLinkDeviceInitializer: Device discovery and initialization (~90 lines)
- Improved code organization following Single Responsibility Principle
- Better maintainability with smaller, focused files

### Technical Details
- Media Foundation shutdown issue: USB device remained active without proper shutdown calls
- Original DeckLinkCaptureDevice.cpp: 677 lines, now ~350 lines + 5 well-organized components
- Each component now has a single, clear responsibility
- Easier to unit test individual components
- Faster compilation due to smaller translation units

## [1.1.5] - 2025-07-15

### Fixed
- **Frame Rate Issue**: NDI now uses actual capture frame rate instead of hardcoded 30fps
- **Statistics Display**: Frame statistics now shown when Enter key is pressed
- **Version Display Bug**: Fixed version display issue (was showing 1.1.0 instead of correct version)
- **Media Foundation Startup Issue**: Fixed race condition in AppController startup
- **DeckLink Frame Drop Crisis**: Fixed 50% frame drop issue by implementing direct frame callbacks

### Changed
- NdiSender v1.0.2: Added frame rate fields to FrameInfo struct
- AppController v1.0.2: Now passes capture frame rate to NDI sender
- Enhanced main.cpp to display final statistics before shutdown
- DeckLink now uses direct callbacks instead of polling (eliminates 10ms delay)
- MediaFoundationCapture v1.0.8: Clean implementation without device-specific hacks

### Technical Details
- NDI sender now uses fps_numerator and fps_denominator from capture device
- Statistics display includes captured/sent/dropped frames and drop percentage
- DeckLinkCapture v1.1.1: Removed polling thread, frames now delivered immediately via callbacks
- Better error recovery with automatic restart on frame timeout

## [1.1.4] - 2025-07-15

### Fixed
- Fixed version display issue (was showing 1.1.0 instead of correct version)
- Fixed race condition in AppController startup causing immediate shutdown
- Fixed DeckLink 50% frame drop issue by implementing direct frame callbacks
- Fixed Media Foundation capture not starting properly

### Changed
- Improved AppController with frame monitoring to detect capture stalls
- DeckLink now uses direct callbacks instead of polling (eliminates 10ms delay)
- Better error recovery with automatic restart on frame timeout

### Technical Details
- AppController v1.0.1: Fixed race condition where main thread checked isRunning() before worker thread started
- DeckLinkCapture v1.1.1: Removed polling thread, frames now delivered immediately via callbacks
- DeckLinkCaptureDevice: Added SetFrameCallback for direct frame delivery
- Added periodic frame monitoring in AppController to detect capture failures

## [1.1.3] - 2025-07-15

### Fixed
- Fixed DeckLink compilation error with device enumerator
- Fixed all outdated documentation
- Completed merge preparation

### Changed
- Updated all documentation to reflect current implementation
- Created comprehensive CHANGELOG
- Updated PR description for production readiness

### Added
- MERGE_PREPARATION.md checklist
- Complete feature comparison documentation

## [1.1.2] - 2025-07-14

### Fixed
- Fixed DeckLink interface mismatch between ICaptureDevice interfaces
- Implemented proper adapter pattern for DeckLink integration
- Fixed thread-safe frame processing

### Technical Details
- Created separate ICaptureDevice interface in capture directory
- DeckLinkCapture now properly adapts between the two interfaces
- Improved frame data handling and conversion

## [1.1.1] - 2025-07-13

### Fixed
- Fixed DeckLink integration compilation errors
- Proper namespace wrapping for DeckLink components
- Compatible header structure between modules

### Technical Details
- Moved DeckLink components to proper namespaces
- Fixed include paths and dependencies
- Resolved circular dependency issues

## [1.1.0] - 2025-07-13

### Added
- **DeckLink Support**: Full support for Blackmagic DeckLink capture cards
  - Automatic format detection (UYVY/BGRA)
  - Robust error recovery
  - Frame statistics and monitoring
  - No-signal handling
  - Serial number tracking for device persistence
- **Capture Type Selection**: Choose between Media Foundation and DeckLink
  - Command line: `-t mf` or `-t dl`
  - Interactive menu for capture type selection
- **Unified Device Interface**: Common interface for all capture devices
- **Format Converter Framework**: Extensible format conversion system
- **Enhanced Error Recovery**: Better handling of device disconnection/reconnection

### Changed
- Improved device enumeration with support for multiple capture backends
- Better error messages and logging
- Enhanced frame statistics reporting

### Technical Details
- Added ICaptureDevice interface for capture abstraction
- Implemented DeckLinkCaptureDevice with full SDK integration
- Created FormatConverterFactory for extensible format conversion
- Improved threading model for capture devices

## [1.0.7] - 2025-07-12

### Fixed
- Fixed Windows macro conflicts (min/max)
- Resolved NOMINMAX definition issues
- Fixed std::min compilation errors

### Added
- Interactive device selection menu with numbered options
- Command-line positional parameter support
- Interactive NDI name input
- "Press Enter to exit" in CLI mode
- Device re-enumeration support

### Changed
- Improved user interface flow
- Better error handling for invalid input
- More intuitive device selection process

## [1.0.6] - 2025-07-12

### Fixed
- Fixed namespace issues in Media Foundation components
- Resolved undefined MF error codes
- Fixed callback interface compatibility

### Technical Details
- Proper namespace usage for media_foundation components
- Added missing error code definitions
- Fixed ICaptureDeviceCallback interface

## [1.0.5] - 2025-07-12

### Added
- Restored all features from reference implementation
- Complete error handling and recovery
- Device re-enumeration on errors
- Format conversion support (NV12, YUY2)

### Fixed
- Frame callback implementation
- Error recovery mechanisms
- Device initialization flow

## [1.0.4] - 2025-07-12

### Fixed
- NDI SDK 6 compatibility
- Updated CMake to handle capitalized directory names
- Fixed NDI DLL discovery

### Changed
- Improved NDI SDK detection logic
- Better error messages for missing SDK

## [1.0.3] - 2025-07-12

### Added
- Integration components
- AppController for application lifecycle
- Proper component initialization flow

### Fixed
- Component integration issues
- Initialization order problems

## [1.0.2] - 2025-07-11

### Fixed
- Media Foundation initialization
- Frame processing pipeline
- Memory management issues

### Added
- Comprehensive error handling
- Debug logging

## [1.0.1] - 2025-07-11

### Fixed
- Initial compilation issues
- CMake configuration
- Project structure

### Added
- Basic Media Foundation capture
- NDI sender implementation
- Windows platform support

## [1.0.0] - 2025-07-11

### Added
- Initial project structure
- CMake build system
- Basic architecture design
- Documentation framework

[1.3.0]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.1.5...v1.2.0
[1.1.5]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.0.7...v1.1.0
[1.0.7]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/zbynekdrlik/ndi-bridge/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/zbynekdrlik/ndi-bridge/releases/tag/v1.0.0
