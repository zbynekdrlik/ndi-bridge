# Capture Device Architecture

## Overview

NDI Bridge supports multiple video capture sources through a unified interface. Each capture implementation follows the `ICaptureDevice` interface, allowing seamless switching between different capture technologies.

## Supported Capture Types

### 1. Media Foundation (Windows)
- **Status**: ✅ Implemented (v1.0.0+)
- **Use Case**: Consumer webcams, HDMI capture devices
- **Location**: `src/windows/media_foundation/`
- **Features**:
  - Wide device compatibility
  - Automatic format conversion
  - Hot-plug support
  - Built into Windows

### 2. DeckLink (Blackmagic)
- **Status**: ✅ Implemented (v1.1.0-v1.1.3)
- **Use Case**: Professional broadcast equipment
- **Location**: `src/windows/decklink/`
- **Features**:
  - SDI/HDMI professional inputs
  - Accurate timing and sync
  - Format auto-detection
  - No-signal handling
  - Serial number tracking
  - Frame statistics

### 3. V4L2 (Linux)
- **Status**: 📋 Planned
- **Use Case**: Linux video devices
- **Location**: `src/linux/v4l2/`

## ICaptureDevice Interface

### Current Implementation Note
There are currently two different `ICaptureDevice` interfaces in the codebase:
1. `src/common/capture_interface.h` - Used by Media Foundation and main.cpp
2. `src/capture/ICaptureDevice.h` - Used by DeckLink core

The DeckLink implementation uses an adapter pattern (`DeckLinkCapture`) to bridge these interfaces.

```cpp
// src/common/capture_interface.h
class ICaptureDevice {
public:
    // Device enumeration
    virtual std::vector<DeviceInfo> enumerateDevices() = 0;
    
    // Capture control
    virtual bool startCapture(const std::string& device_name = "") = 0;
    virtual void stopCapture() = 0;
    virtual bool isCapturing() const = 0;
    
    // Callbacks
    virtual void setFrameCallback(FrameCallback callback) = 0;
    virtual void setErrorCallback(ErrorCallback callback) = 0;
    
    // Error handling
    virtual bool hasError() const = 0;
    virtual std::string getLastError() const = 0;
};
```

## Capture Type Selection

### Command-Line Selection
```bash
# Use Media Foundation (webcams, USB capture)
ndi-bridge.exe -t mf

# Use DeckLink (professional broadcast)
ndi-bridge.exe -t dl

# Interactive selection (default)
ndi-bridge.exe
```

### Interactive Mode
When no capture type is specified, the application prompts:
```
Select capture type:
1. Media Foundation (webcams, USB capture)
2. DeckLink (professional broadcast cards)
Enter choice (1-2):
```

## Implementation Details

### Media Foundation
- Uses Windows Media Foundation API
- Supports various pixel formats (YUY2, NV12, MJPEG)
- Automatic format conversion to UYVY for NDI
- Handles device disconnection/reconnection

### DeckLink
- Uses Blackmagic DeckLink SDK
- Native UYVY and BGRA support
- Professional features:
  - Format change detection
  - No-signal handling
  - Frame timing statistics
  - Device serial number tracking

## Adding New Capture Types

1. Create directory: `src/[platform]/[capture_type]/`
2. Implement the common `ICaptureDevice` interface
3. Add to CMakeLists.txt with optional flag
4. Update capture device factory in main.cpp
5. Add command-line option support
6. Create documentation

## Performance Considerations

- All capture devices output UYVY format for NDI compatibility
- Format conversion happens in capture implementation
- Zero-copy operations where possible
- Dedicated capture thread per device
- Frame dropping on queue overflow (DeckLink)
- Minimal buffering for low latency

## Error Handling

### Common Error Scenarios
1. **Device not found**: Clear error message with device list
2. **Device in use**: Retry with delay or suggest alternatives
3. **Format unsupported**: Automatic format conversion
4. **Signal lost**: Continuous monitoring and reconnection
5. **Driver issues**: Helpful troubleshooting messages

### Recovery Mechanisms
- Automatic device re-enumeration
- Configurable retry logic
- Graceful degradation
- Clear error reporting to user
