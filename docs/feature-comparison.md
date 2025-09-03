# Feature Comparison: Evolution from v1.0.0 to v1.1.3

This document tracks the evolution of Media Bridge features across all versions.

## Version 1.1.3 (Current) - Production Ready

### Major Features Summary

| Feature Category | Status | Version | Notes |
|-----------------|--------|---------|-------|
| **Media Foundation** | ✅ Complete | v1.0.0+ | Windows webcams and HDMI capture |
| **DeckLink Support** | ✅ Complete | v1.1.3 | Professional broadcast equipment |
| **NDI Streaming** | ✅ Complete | v1.0.0+ | Low-latency network streaming |
| **Cross-platform Architecture** | 📋 Framework | v1.0.0+ | Linux support planned |
| **Error Recovery** | ✅ Complete | v1.0.0+ | Automatic reconnection and retry |
| **Interactive UI** | ✅ Complete | v1.0.5+ | User-friendly device selection |

## Feature Evolution by Version

### Core Features

| Feature | v1.0.0 | v1.0.7 | v1.1.0 | v1.1.3 | Notes |
|---------|--------|--------|--------|--------|-------|
| **Media Foundation Capture** | ✅ | ✅ | ✅ | ✅ | Stable since v1.0.0 |
| **DeckLink Capture** | ❌ | ❌ | 🔄 | ✅ | Completed in v1.1.3 |
| **NDI Streaming** | ✅ | ✅ | ✅ | ✅ | Core functionality |
| **Format Conversion** | ✅ | ✅ | ✅ | ✅ | YUY2→UYVY, NV12→UYVY, BGRA→UYVY |
| **Capture Type Selection** | ❌ | ❌ | ✅ | ✅ | `-t mf` or `-t dl` |
| **Multiple Device Support** | ✅ | ✅ | ✅ | ✅ | Unified interface |

### User Interface Features

| Feature | v1.0.0 | v1.0.5 | v1.0.7 | v1.1.3 | Notes |
|---------|--------|--------|--------|--------|-------|
| **Interactive Device Menu** | ❌ | ✅ | ✅ | ✅ | Numbered selection |
| **Command-line Options** | ✅ | ✅ | ✅ | ✅ | Full CLI support |
| **Positional Parameters** | ❌ | ✅ | ✅ | ✅ | `program "device" "name"` |
| **List Devices (-l)** | ✅ | ✅ | ✅ | ✅ | Per capture type |
| **Interactive NDI Name** | ❌ | ✅ | ✅ | ✅ | Prompts for name |
| **Version Display** | ✅ | ✅ | ✅ | ✅ | Shows on startup |
| **Help Display (-h)** | ✅ | ✅ | ✅ | ✅ | Comprehensive help |

### Technical Features

| Feature | v1.0.0 | v1.0.7 | v1.1.0 | v1.1.3 | Notes |
|---------|--------|--------|--------|--------|-------|
| **Device Re-enumeration** | ✅ | ✅ | ✅ | ✅ | Auto-reconnect |
| **Signal Handling** | ✅ | ✅ | ✅ | ✅ | Clean shutdown |
| **Frame Statistics** | ✅ | ✅ | ✅ | ✅ | FPS monitoring |
| **Modular Architecture** | ✅ | ✅ | ✅ | ✅ | Clean separation |
| **Thread-safe Processing** | ✅ | ✅ | ✅ | ✅ | Per-device threads |
| **Format Converter Framework** | ❌ | ❌ | ✅ | ✅ | Extensible design |
| **Serial Number Tracking** | ❌ | ❌ | ✅ | ✅ | DeckLink persistence |
| **No-signal Handling** | ❌ | ❌ | ✅ | ✅ | Professional feature |

### DeckLink-Specific Features (v1.1.0+)

| Feature | Status | Notes |
|---------|--------|-------|
| **Device Enumeration** | ✅ | Lists all DeckLink devices |
| **Format Auto-detection** | ✅ | Detects input format |
| **UYVY/BGRA Support** | ✅ | Native formats |
| **Serial Number Tracking** | ✅ | Device persistence |
| **No-signal Detection** | ✅ | Handles signal loss |
| **Rolling FPS Calculation** | ✅ | 60-second average |
| **Frame Queue Management** | ✅ | Drops on overflow |
| **Hot-plug Support** | ✅ | Reconnect on unplug |

## Command-Line Interface

### Current Options (v1.1.3)

| Option | Description | Since |
|--------|-------------|-------|
| `-t, --type <type>` | Capture type: `mf` or `dl` | v1.1.0 |
| `-d, --device <name>` | Device name or number | v1.0.0 |
| `-n, --ndi-name <name>` | NDI stream name | v1.0.0 |
| `-l, --list-devices` | List available devices | v1.0.0 |
| `-v, --verbose` | Enable verbose logging | v1.0.0 |
| `--no-retry` | Disable auto-retry | v1.0.0 |
| `--retry-delay <ms>` | Retry delay (default: 5000) | v1.0.0 |
| `--max-retries <n>` | Max retries (-1 = infinite) | v1.0.0 |
| `-h, --help` | Show help | v1.0.0 |
| `--version` | Show version | v1.0.0 |

## Architecture Changes

### v1.0.x Series
- Basic modular architecture
- Platform abstraction layer
- Single capture interface

### v1.1.x Series
- Dual capture interfaces (compatibility issue)
- Adapter pattern for DeckLink
- Format converter framework
- Enhanced error handling
- Professional broadcast features

## Known Issues

1. **Two ICaptureDevice interfaces** (v1.1.0+)
   - `src/common/capture_interface.h` (Media Foundation)
   - `src/capture/ICaptureDevice.h` (DeckLink)
   - TODO: Consolidate in future version

2. **Linux Support**
   - Framework exists but not implemented
   - Planned for future release

## Summary

Media Bridge v1.1.3 represents a mature, production-ready application with:
- ✅ Complete Media Foundation support
- ✅ Complete DeckLink support
- ✅ Professional broadcast features
- ✅ Robust error handling
- ✅ User-friendly interface
- ✅ Extensible architecture

The application has evolved from a basic capture tool to a professional-grade NDI bridge supporting both consumer and broadcast equipment.
