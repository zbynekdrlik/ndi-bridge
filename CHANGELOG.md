# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.3] - 2025-07-15

### Fixed
- Fixed DeckLink enumerator compilation errors (incorrect usage of `EnumerateDevices()`)
- Resolved all syntax errors in `decklink_capture.cpp`

### Changed
- Improved error handling in DeckLink device enumeration
- Updated documentation to reflect current state

## [1.1.2] - 2025-07-15

### Fixed
- Fixed interface mismatch between DeckLink and main application
- Created adapter pattern to bridge different `ICaptureDevice` interfaces
- Added missing thread includes for frame processing

### Added
- `DeckLinkCapture` adapter class implementing correct interface
- Thread-safe frame processing for DeckLink devices

## [1.1.1] - 2025-07-15

### Fixed
- Fixed DeckLink include paths in main.cpp
- Corrected namespace wrapping for DeckLink classes
- Resolved compilation errors with DeckLink integration

## [1.1.0] - 2025-07-15

### Added
- **DeckLink Support**: Full support for Blackmagic DeckLink capture cards
  - Device enumeration and selection
  - Automatic format detection
  - No-signal handling
  - Serial number tracking for device persistence
  - Rolling FPS calculation
  - Robust error recovery
- **Capture Type Selection**: New `-t` parameter for selecting capture type (mf/dl)
- **Format Converter Framework**: Extensible format conversion system
  - UYVY to NDI conversion
  - BGRA to NDI conversion
  - Factory pattern for format converters
- **Enhanced Error Handling**: Comprehensive error recovery for professional use

### Changed
- Refactored capture device architecture to support multiple backends
- Updated command-line interface to support capture type selection
- Improved device enumeration with unified interface

### Documentation
- Added DeckLink setup guide
- Added DeckLink SDK setup instructions
- Added architecture documentation
- Included reference implementation for DeckLink

## [1.0.7] - 2025-07-11

### Fixed
- Resolved Windows macro conflicts (min/max)
- Fixed compilation errors in Media Foundation code

### Changed
- Improved Windows compatibility
- Enhanced error messages

## [1.0.6] - 2025-07-11

### Fixed
- Fixed various compilation errors
- Resolved include path issues

## [1.0.5] - 2025-07-11

### Added
- Restored interactive device selection menu
- Re-implemented command-line positional parameters
- Added interactive NDI name input
- Restored "Press Enter to exit" functionality
- Re-enabled device re-enumeration on "R" key

## [1.0.4] - 2025-07-11

### Added
- NDI SDK configuration in CMake
- Support for NDI 5 and NDI 6 SDK
- Automatic NDI DLL copying

### Fixed
- NDI SDK path detection
- Build configuration issues

## [1.0.3] - 2025-07-11

### Added
- Integration components
- Application controller
- Format converter interfaces

## [1.0.2] - 2025-07-11

### Added
- Media Foundation refactoring
- Improved error handling
- Better device management

## [1.0.1] - 2025-07-11

### Added
- NDI sender implementation
- Basic format conversion

## [1.0.0] - 2025-07-11

### Added
- Initial project structure
- Media Foundation capture support
- Basic NDI streaming
- Command-line interface
- Windows platform support

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
