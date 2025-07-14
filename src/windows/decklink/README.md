# DeckLink Capture Implementation

## Overview

This directory contains the Blackmagic DeckLink capture implementation for NDI Bridge.

## Files

- `decklink_capture.h/cpp` - Main capture implementation (ICaptureDevice)
- `decklink_discovery.h/cpp` - Device enumeration and detection
- `decklink_callback.h/cpp` - Frame callback handlers
- `decklink_utils.h/cpp` - Utility functions and helpers

## DeckLink SDK Requirements

- Minimum SDK Version: 12.0
- Required headers:
  - `DeckLinkAPI.h`
  - `DeckLinkAPIVersion.h`
  - `DeckLinkAPIDiscovery.h`

## Implementation Notes

### COM Initialization
DeckLink requires COM to be initialized in multi-threaded mode:
```cpp
CoInitializeEx(nullptr, COINIT_MULTITHREADED);
```

### Output Format
All captured frames are converted to UYVY format for NDI compatibility.

### Thread Safety
DeckLink callbacks occur on a separate thread. Proper synchronization is required.

## Building

Enable DeckLink support in CMake:
```bash
cmake -DUSE_DECKLINK=ON ..
```
