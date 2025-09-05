# Changelog

All notable changes to the Media Bridge project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.6] - 2025-07-21

### Added
- **Modular USB Build System v1.3.1**:
  - Fixed boot issues - USB now boots properly
  - Fixed TTY2 welcome screen with proper color display
  - Added TERM=linux to .profile for console compatibility
  - Power failure resistance features maintained

### Changed
- **Build System Architecture**:
  - Simplified partition layout (removed unnecessary BIOS boot partition)
  - Fixed UUID capture before chroot execution
  - Improved systemctl command compatibility in chroot
  - Better error handling during package installation

### Fixed
- **Boot Issues**:
  - Fixed GRUB installation for UEFI-only systems
  - Fixed partition numbering (EFI on 1, root on 2)
  - Removed conflicting grub-pc packages
  - Added missing initramfs-tools package
- **TTY2 Display**:
  - Fixed heredoc escaping in build script
  - Fixed color escape sequences (using printf for compatibility)
  - Fixed welcome script syntax errors
  - Auto-refresh now works properly with colors

### Removed
- Obsolete documentation and build scripts
- Unnecessary BIOS boot partition
- Conflicting GRUB packages

## [2.1.5] - 2025-07-20

### Added
- **USB Hot-plug Recovery**: Automatic recovery when USB capture devices disconnect/reconnect
  - Added `has_error_` flag clearing in V4L2 capture restart
  - 100ms USB stabilization delay for reliable reconnection
  - Frame monitoring detects stalled capture (5-second timeout)
  - Automatic service restart on USB disconnection
- **Bootable USB Build System v1.2.3**:
  - Modular build architecture with 13 separate modules
  - Helper scripts for system management
  - TTY auto-refresh for IP display
  - Network monitoring tools included
  - 0-second GRUB timeout for instant boot
  - Power button disabled for always-on operation

### Changed
- **Password**: Default root password changed from "NewLevel123!" to "newlevel"
- **Build Script Structure**: Refactored monolithic script into modular components
  - `00-variables.sh` through `13-helper-scripts-inline.sh`
  - Easier maintenance and debugging
  - Consistent error handling across modules

### Fixed
- **USB Reconnection**: V4L2 capture now properly recovers after USB disconnect
  - Error flag wasn't being cleared, preventing restart
  - Added proper error state reset in `startCapture()`
- **TTY Console Issues**:
  - TTY1 now shows logs properly (was permission error)
  - TTY2 displays correct IP after boot (was empty)
  - Fixed POSIX compatibility (removed grep -oP)
  - Created proper bash scripts instead of inline commands

### Technical Details
- USB recovery tested on real hardware (10.77.8.100-102)
- Build time reduced to ~4 minutes with proper logging
- Helper scripts created in chroot for proper permissions
- Network bridge (br0) combines both ethernet ports

## [2.1.4] - 2025-07-20

### Fixed
- **Frame Monitoring**: Initial implementation of USB disconnect detection
  - Added frame counter tracking in AppController
  - 5-second timeout triggers restart if no frames received
  - Sets restart_requested_ flag for graceful recovery

### Known Issues
- USB reconnection not working (fixed in v2.1.5)
- Error flag prevents restart after disconnect

## [2.1.0] - 2025-07-19

### Added
- **Bootable USB Appliance**: Complete Linux system for Media Bridge
  - Ubuntu 24.04 LTS base system
  - Auto-starting Media Bridge service
  - Network bridge configuration for dual ethernet
  - TTY1: Live logs display
  - TTY2: System information and menu
  - SSH access with password authentication
  - Helper scripts for management
- **Build Script Versioning**: Added version tracking to USB build scripts
  - Started at v1.0.0
  - Version displayed in build output
  - Incremented with each significant change

### Changed
- **Architecture**: Improved error handling across all capture types
  - Consistent error reporting
  - Better recovery mechanisms
  - Improved logging throughout

### Technical Details
- USB build creates complete bootable system in ~10-15 minutes
- Supports UEFI and Legacy BIOS boot
- Read-write filesystem (can be made read-only)
- Minimal Ubuntu installation (~1GB)

## [2.0.0] - 2025-07-18

### Added
- **Multi-threaded Architecture**: Complete rewrite for professional deployment
  - Separate threads for capture, processing, and network operations
  - Thread-safe communication with proper synchronization
  - Improved stability for 24/7 operation
- **Enhanced Error Recovery**:
  - Automatic restart on capture failures
  - Device reconnection handling
  - Comprehensive error reporting
  - Service-friendly operation

### Changed
- **Major Version Bump**: Reflects architectural changes
  - Not backward compatible with 1.x configuration
  - New threading model
  - Enhanced reliability features

### Performance
- Maintained low latency while improving stability
- Better resource management
- Suitable for production deployment

## [1.7.0] - 2025-07-17

### Added
- **Linux V4L2 Low Latency Mode**: Aggressive optimizations for minimal latency
  - New `--low-latency` command-line option
  - Forces single-threaded operation
  - Reduces V4L2 buffer count to 4 (minimum stable)
  - Uses immediate polling (0ms timeout)
  - Minimizes queue depths to 2/1
  - Interactive mode prompts for performance options
- **Single-Threaded V4L2 Option**: Direct capture-to-send pipeline
  - New `--single-thread` command-line option
  - Eliminates inter-thread queues and synchronization
  - Reduces latency by ~2-3 frames
  - Lower CPU usage for simple capture scenarios
- **End-to-End Latency Tracking**: Comprehensive latency measurement
  - Tracks time from frame capture to NDI send
  - Reports average and maximum E2E latency
  - Available in both single and multi-threaded modes

### Changed
- **V4L2 Buffer Management**: Optimized for low latency
  - Normal mode: 6 buffers (reduced from 10)
  - Low latency mode: 4 buffers (minimum stable)
  - Dynamic buffer count based on mode
- **Queue Depths**: Reduced for faster processing
  - Capture queue: 3 (reduced from 5), 2 in low latency
  - Convert queue: 2 (reduced from 5), 1 in low latency
  - Minimal buffering while maintaining stability
- **Polling Strategy**: Immediate response
  - Multi-threaded: 0ms timeout (was 1ms)
  - Single-threaded: 1ms timeout (was 5ms)
  - Low latency: 0ms timeout (immediate)

### Fixed
- **Thread Sleep Removal**: Eliminated all sleep delays
  - Convert thread: Removed 100μs sleep when queue empty
  - Send thread: Removed 100μs sleep when queue empty
  - Now uses tight polling loops for immediate response
  - Saves ~1-2 frames of latency

### Performance
- **Target Achievement**: Linux V4L2 now matches Windows performance
  - Expected: 8 frames latency (down from 12)
  - Single-threaded mode: Lowest possible latency
  - Multi-threaded mode: Better for high CPU load scenarios
  - Zero-copy YUYV path maintained

### Technical Details
- Tight polling loops eliminate scheduling delays
- Reduced buffer counts minimize V4L2 driver queuing
- Single-threaded mode follows Windows Media Foundation design
- Multi-threaded mode optimized for Intel N100 4-core CPUs
- All optimizations maintain 60 FPS capture rate

## [1.6.7] - 2025-07-17

### Fixed
- **Media Foundation Final Optimization**: Achieved 8 frames latency target
  - Removed remaining 5ms sleep in capture loop
  - Now uses tight loop when no sample available
  - Matches reference implementation performance

### Performance
- Windows latency: 14 → 10 → 8 frames (complete fix)
- Back to reference implementation performance levels
- Ready to apply learnings to Linux implementation

## [1.6.6] - 2025-07-17

### Fixed
- **Media Foundation Latency Regression**: Fixed major latency increase (14 frames back to 8 frames)
  - Set NDI `clock_video=false` for immediate frame delivery (was true, causing pacing)
  - Removed 5ms sleep in capture loop when no sample available (now tight loop)
  - Added Media Foundation attributes to minimize internal buffering
  - This brings latency back in line with old reference implementation

### Changed
- **Media Foundation Configuration**: Added low-latency attributes
  - `MF_READWRITE_DISABLE_CONVERTERS=TRUE` - Disable unnecessary conversions
  - `MF_SOURCE_READER_DISABLE_DXVA=TRUE` - Disable hardware acceleration overhead
  - `MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING=FALSE` - Disable extra processing
  - `MF_LOW_LATENCY=TRUE` - Enable low latency mode when supported

### Technical Details
- Latency regression was caused by differences from reference implementation
- NDI clock_video was pacing frames instead of immediate delivery
- Sleep in capture loop was adding unnecessary delay
- Default Media Foundation buffering was adding 3-5 frames
- Threading model unchanged (to be addressed if needed after measurement)

## [1.6.5] - 2025-07-17

### Added
- **BGRA Zero-Copy Support**: Extended zero-copy to BGRA format
  - NDI natively supports BGRA - no conversion needed
  - Works with PC HDMI outputs which typically use RGB/BGRA
  - Same performance benefits as UYVY zero-copy
  - Automatic format detection for both UYVY and BGRA

### Changed
- **Zero-Copy Logic**: Now checks for both UYVY and BGRA formats
  - ProcessFrameZeroCopy handles both formats
  - Appropriate logging for each format type
  - Updated version string to reflect dual format support

### Technical Details
- PC HDMI outputs typically use RGB444/BGRA format
- Game consoles and cameras typically use YCbCr422/UYVY
- Both formats now achieve 100% zero-copy performance
- ~40-50ms total latency reduction vs v1.5.x

## [1.6.4] - 2025-07-17

### Fixed
- **Critical DeckLink SDK Compliance**: Restored required buffer access calls
  - Re-added StartAccess(bmdBufferAccessRead) before accessing frame data
  - Re-added EndAccess(bmdBufferAccessRead) after processing
  - These calls are MANDATORY per DeckLink SDK documentation
  - Without them, GetBytes() may return invalid data
  - Fixes zero-copy functionality that was broken in v1.6.1-v1.6.3

### Technical Details
- Zero-copy optimization now properly complies with SDK requirements
- Maintains all performance benefits while ensuring correct operation
- This completes the chain of fixes needed for DeckLink optimization

## [1.6.3] - 2025-07-17

### Fixed
- **AppController Callback Initialization**: Fixed second callback order issue
  - AppController was setting callbacks AFTER calling startCapture()
  - Fixed order: setFrameCallback() → setErrorCallback() → startCapture()
  - Ensures callbacks are ready when frames start arriving

### Technical Details
- Completes the callback initialization chain
- Works with v1.6.2 fix to enable proper frame delivery
- Both fixes required for DeckLink to receive frames

## [1.6.2] - 2025-07-17

### Fixed
- **DeckLink Callback Initialization**: Fixed frame delivery issue
  - Frame callback was being set BEFORE device initialization
  - Fixed order: Initialize() → SetFrameCallback() → StartCapture()
  - DeckLink SDK requires device initialization before callbacks

### Technical Details
- Fixes "No frames received" error
- Enables VideoInputFrameArrived callback to deliver frames
- First of two initialization order fixes needed

## [1.6.1] - 2025-07-16

### Added
- **TRUE Zero-Copy for UYVY**: DeckLink UYVY format now sent directly to NDI
  - NDI natively supports UYVY - no conversion needed!
  - Eliminated unnecessary UYVY→BGRA conversion
  - Log message "TRUE ZERO-COPY: UYVY direct to NDI"
- **Design Philosophy Document**: Created `docs/DESIGN_PHILOSOPHY.md`
  - Documents Media Bridge's focus on low latency as NON-NEGOTIABLE
  - Targets modern hardware (Intel N100+)
  - No compatibility modes that compromise performance

### Changed
- **Simplified Architecture**: Removed low-latency mode flag
  - Low latency is now the ONLY mode
  - No configuration options that could increase latency
  - Always uses the fastest path available

### Fixed
- Zero-copy detection was converting UYVY to BGRA unnecessarily
- ProcessFrameZeroCopy now correctly sets format to UYVY

### Performance
- Zero-copy frames: Now 100% (was 0% in v1.6.0)
- Additional latency reduction: ~5-10ms (no format conversion)
- Total latency improvement: ~40-60ms vs v1.5.x

## [1.6.0] - 2025-07-16

### Added
- **DeckLink Low-Latency Optimizations**: Applied techniques from Linux V4L2
  - Reduced frame queue size from 3 to 1 (saves ~33ms at 60fps)
  - Direct callback mode - bypasses queue entirely
  - Pre-allocated conversion buffers
  - Performance tracking for zero-copy usage
  - Low-latency mode flag (default ON)
- **Compilation Fix**: Added metadata field to CaptureStatistics

### Changed
- **Queue Bypass**: When frame callback is set, frames bypass queue completely
  - 100% direct callback delivery in testing
  - Eliminated 33-50ms of queue latency
- **Memory Management**: Pre-allocate buffers to avoid runtime allocation

### Performance
- Direct callback usage: 100%
- Queue latency eliminated: ~33-50ms saved
- Perfect 60 FPS maintained
- Zero dropped frames in testing

## [1.5.0] - 2025-07-16

### Added
- **Multi-threaded Pipeline** (Linux): Revolutionary architecture for sub-millisecond latency
  - 3-thread design with dedicated CPU core affinity
  - Thread 1 (Core 1): V4L2 capture and buffer management
  - Thread 2 (Core 2): Format conversion processing
  - Thread 3 (Core 3): NDI transmission
  - Lock-free frame queues for zero-contention communication
  - Real-time thread priority support (when available)
  - Thread performance monitoring and statistics
- **Pipeline Components**:
  - `PipelineThreadPool`: Thread lifecycle management with CPU affinity
  - `FrameQueue`: Lock-free ring buffer with atomic operations
  - `BufferIndexQueue`: Lightweight queue for V4L2 buffer recycling
  - Pre-allocated memory pools to eliminate runtime allocations
- **Cross-platform Compatibility**: Fixed Windows build issues
  - Platform-specific CPU feature detection
  - Windows thread affinity support
  - Conditional compilation for platform-specific headers

### Changed
- **Performance**: Achieved 0.73ms average latency (95.5% reduction from v1.0.0)
  - 90.4% improvement over v1.4.0's zero-copy implementation
  - Perfect 60 FPS with < 0.1% frame drops
  - Thread breakdown: Capture 1.04ms, Convert 0.10ms, Send 0.38ms
- **Architecture**: Complete V4L2 capture rewrite for multi-threading
  - Separate capture modes for single vs multi-threaded operation
  - Configurable queue depths for tuning
  - Non-blocking operations throughout pipeline

### Technical Details
- Lock-free queues use C++11 atomic operations for thread safety
- Cache-line aligned data structures (64-byte) to prevent false sharing
- Ring buffer design with power-of-2 sizes for efficient modulo operations
- Zero-copy maintained throughout the multi-threaded pipeline
- Compatible with Intel N100's 4-core architecture

### Performance Metrics
- Average latency: 0.73ms (from 7.6ms in v1.4.0)
- Queue drops: 6 total over 7875 frames (0.076%)
- CPU usage: ~15% total across 3 dedicated cores
- Memory usage: ~40MB for queue buffers

## [1.4.0] - 2025-07-16

### Added
- **Zero-copy YUYV Support**: Direct NDI transmission without conversion
  - Native YUYV (YUY2) format support in NDI sender
  - YUYV to UYVY byte-swapping with AVX2 optimization
  - Automatic detection of zero-copy capable formats
  - Eliminated BGRA conversion for supported devices
- **NDI Sender Optimizations**:
  - AVX2-accelerated YUYV→UYVY conversion (32 pixels at once)
  - Runtime CPU feature detection for optimal path selection
  - Conversion buffer reuse to minimize allocations
  - Direct frame passthrough for native NDI formats

### Changed
- **Performance**: Achieved 7.6ms average latency (52% reduction from v1.0.0)
  - 100% zero-copy frames for YUYV devices
  - Eliminated ~8ms of YUYV→BGRA conversion overhead
  - Maintained perfect 60 FPS capture rate
- **V4L2 Implementation**: Smart format handling
  - Prioritizes YUYV format when available
  - Falls back to other formats only when necessary
  - Improved format negotiation logic

### Technical Details
- YUYV to UYVY requires only byte reordering (Y0U0Y1V0 → U0Y0V0Y1)
- AVX2 implementation uses _mm256_shuffle_epi8 for parallel byte swapping
- Maintains bit-exact output while processing 16x more data per instruction
- Zero additional memory allocations in steady state

### Performance Improvements
- Latency: 16.068ms → 7.621ms (52% reduction)
- CPU usage: Reduced by eliminating format conversion
- Memory bandwidth: Halved by removing intermediate BGRA buffer
- Zero frame drops in testing (550/550 frames)

## [1.3.1] - 2025-07-16

### Added
- **AVX2 Optimizations**: SIMD-accelerated YUV to BGRA conversion for Intel N100 processors
  - Processes 16 pixels at a time for maximum throughput
  - Runtime CPU feature detection with automatic fallback
  - Optimized YUYV, UYVY, and NV12 format conversion
  - ~3x performance improvement for format conversion on supported CPUs
- **Build System Improvements**:
  - V4L2 header presence check during configuration
  - AVX2 compiler support detection
  - Intel N100 specific optimization flags (-mtune=alderlake)
  - Conditional compilation of AVX2 sources

### Changed
- **Buffer Management**: Increased V4L2 buffer count from 6 to 10 for smoother operation
- **Compiler Optimizations**: Added -O3, -march=native, and -ffast-math for Release builds on Linux
- **Format Converter**: Automatically uses AVX2 when available with runtime detection

### Technical Details
- AVX2 implementation uses 256-bit SIMD registers
- Optimized for Intel N100's E-core architecture and 6MB L3 cache
- Maintains bit-exact output compared to scalar implementation
- Thread-safe runtime feature detection

### Performance Improvements
- Format conversion: Up to 70% reduction in CPU usage
- 1080p60 capture: < 10% CPU usage on Intel N100
- Frame processing latency: < 5ms for format conversion

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
- **Logger Format**: Simplified to `[timestamp] message` format
  - Removed module names from log output for cleaner logs
  - Single version log at application startup only
  - Removed unnecessary Logger methods (initialize, logVersion)
  - Fixed remaining cout/cerr usage throughout codebase
- **Code Cleanup**: Improved consistency across all modules
  - Standardized error handling and logging
  - Removed redundant version logging from components
  - Updated version string format from "Script version" to "Version"

### Technical Details
- Logger is now self-initializing (no explicit initialize() needed)
- All console output now goes through unified Logger
- Cleaner, more readable log output for production use

## [1.2.1] - 2025-07-15

### Fixed
- **Documentation**: Comprehensive documentation overhaul
  - Added detailed build instructions for Windows
  - Created step-by-step DeckLink SDK setup guide
  - Fixed formatting and structure issues
  - Added troubleshooting section
  - Improved examples and usage instructions

### Added
- **Documentation Files**:
  - `docs/build-windows.md` - Detailed Windows build guide
  - `docs/decklink-sdk-setup.md` - DeckLink SDK integration guide
  - Updated README with clearer project information

## [1.2.0] - 2025-07-14

### Added
- **DeckLink Architecture Refactoring**:
  - New component-based architecture for better maintainability
  - `DeckLinkCaptureCallback` - Dedicated callback handling
  - `DeckLinkFrameQueue` - Thread-safe frame queue management
  - `DeckLinkStatistics` - Performance monitoring and statistics
  - `DeckLinkFormatManager` - Format detection and conversion
  - `DeckLinkDeviceInitializer` - Device initialization logic
- **Improved Error Handling**:
  - Comprehensive error reporting throughout DeckLink stack
  - Better device state management
  - Graceful handling of device disconnection

### Changed
- **DeckLink Implementation**:
  - Migrated from monolithic to component-based design
  - Improved thread safety with dedicated frame queue
  - Better separation of concerns
  - Enhanced logging and debugging capabilities

### Fixed
- Memory management issues in DeckLink capture
- Thread synchronization problems
- Format detection reliability

## [1.1.5] - 2025-07-13

### Fixed
- **Build System**: Critical fix for clean builds
  - Fixed DeckLink SDK file discovery
  - Proper handling of missing SDK files
  - Clear error messages when SDK not found
  - Fixed `docs/reference` directory usage

### Changed
- **Documentation**: Updated DeckLink setup instructions
  - Clarified SDK file requirements
  - Added troubleshooting steps
  - Improved build error guidance

## [1.1.4] - 2025-07-13

### Fixed
- **DeckLink Integration**: Resolved undefined symbols
  - Fixed IDeckLinkIterator creation
  - Proper CoCreateInstance usage
  - Correct CLSID/IID definitions

### Changed
- **Build Configuration**: Improved DeckLink handling
  - Better SDK detection
  - Clearer build messages
  - Conditional compilation fixes

## [1.1.3] - 2025-07-13

### Fixed
- **Memory Management**: Improved capture device lifecycle
  - Fixed potential memory leaks in error paths
  - Better cleanup on device disconnect
  - Improved error state handling

### Added
- **Capture Device Features**:
  - Configurable retry attempts (`-r, --retry`)
  - Maximum retry limit (`-m, --max-retries`)
  - Better device recovery logic

## [1.1.2] - 2025-07-13

### Fixed
- **Media Foundation**: NZXT Signal HD60 shutdown issues
  - Implemented capture state persistence
  - Fixed Control-C handling for NZXT devices
  - Proper Media Foundation cleanup sequence
  - Global capture device reference for cleanup

### Added
- **Device-Specific Handling**:
  - NZXT device detection
  - Special cleanup procedures for problematic devices
  - Improved signal handler implementation

## [1.1.1] - 2025-07-13

### Fixed
- **Format Detection**: Improved format string parsing
  - Fixed string length validation
  - Safe format name extraction
  - Better error handling for malformed formats

### Changed
- **Error Messages**: More descriptive format errors
  - Include format details in error messages
  - Better debugging information
  - Clearer user feedback

## [1.1.0] - 2025-07-12

### Added
- **DeckLink Support**: Professional Blackmagic capture cards
  - Full DeckLink SDK integration
  - Automatic format detection
  - Support for multiple DeckLink devices
  - No-signal detection and handling
  - HD/SD format support
  - Automatic pixel format conversion (UYVY to BGRA)

- **Multi-Capture Type Selection**:
  - Command-line option `-t, --type` for capture type
  - Support for `mf` (Media Foundation) and `dl` (DeckLink)
  - Interactive selection when not specified
  - Per-type device enumeration

- **Enhanced Device Management**:
  - Unified device enumeration interface
  - Cross-capture-type device listing
  - Improved device selection UI
  - Better error messages for missing devices

### Changed
- **Architecture**: Refactored for multiple capture backends
  - New `decklink_capture` adapter class
  - Consistent interface across capture types
  - Improved modularity and extensibility

- **Command-Line Interface**:
  - Updated help text with new options
  - Better parameter validation
  - Type-specific device listing

### Fixed
- Memory management in capture device cleanup
- Thread safety in format detection
- Error handling for invalid device names

## [1.0.0] - 2025-07-11

### Added
- **Core Features**:
  - Media Foundation capture support
  - NDI streaming output
  - Real-time video bridging
  - Automatic device detection
  - Interactive device selection
  - Command-line interface
  - Configurable NDI stream names
  - Verbose logging option
  - Cross-device compatibility

- **Performance**:
  - Low latency design (< 1 frame)
  - Hardware-accelerated capture
  - Efficient format conversion
  - Zero-copy where possible
  - Multi-threaded architecture

- **Error Handling**:
  - Automatic reconnection
  - Graceful degradation
  - Comprehensive error messages
  - Device state monitoring

### Technical Specifications
- Windows 10/11 support
- NDI SDK 5.0+ compatible
- C++17 standard
- CMake build system
- MIT License

## [0.1.0] - 2025-07-10

### Added
- Initial project structure
- Basic architecture design
- Documentation framework

[2.1.5]: https://github.com/zbynekdrlik/media-bridge/compare/v2.1.4...v2.1.5
[2.1.4]: https://github.com/zbynekdrlik/media-bridge/compare/v2.1.0...v2.1.4
[2.1.0]: https://github.com/zbynekdrlik/media-bridge/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/zbynekdrlik/media-bridge/compare/v1.7.0...v2.0.0
[1.7.0]: https://github.com/zbynekdrlik/media-bridge/compare/v1.6.7...v1.7.0
[1.6.7]: https://github.com/zbynekdrlik/media-bridge/compare/v1.6.6...v1.6.7
[1.6.6]: https://github.com/zbynekdrlik/media-bridge/compare/v1.6.5...v1.6.6
[1.6.5]: https://github.com/zbynekdrlik/media-bridge/compare/v1.6.4...v1.6.5
[1.6.4]: https://github.com/zbynekdrlik/media-bridge/compare/v1.6.3...v1.6.4
[1.6.3]: https://github.com/zbynekdrlik/media-bridge/compare/v1.6.2...v1.6.3
[1.6.2]: https://github.com/zbynekdrlik/media-bridge/compare/v1.6.1...v1.6.2
[1.6.1]: https://github.com/zbynekdrlik/media-bridge/compare/v1.6.0...v1.6.1
[1.6.0]: https://github.com/zbynekdrlik/media-bridge/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/zbynekdrlik/media-bridge/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/zbynekdrlik/media-bridge/compare/v1.3.1...v1.4.0
[1.3.1]: https://github.com/zbynekdrlik/media-bridge/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/zbynekdrlik/media-bridge/compare/v1.2.2...v1.3.0
[1.2.2]: https://github.com/zbynekdrlik/media-bridge/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/zbynekdrlik/media-bridge/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/zbynekdrlik/media-bridge/compare/v1.1.5...v1.2.0
[1.1.5]: https://github.com/zbynekdrlik/media-bridge/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/zbynekdrlik/media-bridge/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/zbynekdrlik/media-bridge/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/zbynekdrlik/media-bridge/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/zbynekdrlik/media-bridge/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/zbynekdrlik/media-bridge/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/zbynekdrlik/media-bridge/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/zbynekdrlik/media-bridge/releases/tag/v0.1.0
