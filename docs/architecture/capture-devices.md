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
- **Status**: 🔄 In Development (v1.1.0)
- **Use Case**: Professional broadcast equipment
- **Location**: `src/windows/decklink/`
- **Features**:
  - SDI/HDMI professional inputs
  - Accurate timing and sync
  - Embedded audio support
  - Timecode support
  - Interlaced video handling

### 3. V4L2 (Linux)
- **Status**: 📋 Planned
- **Use Case**: Linux video devices
- **Location**: `src/linux/v4l2/`

## ICaptureDevice Interface

```cpp
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

### Auto-Detection Logic
1. Check for DeckLink devices (if SDK available)
2. Check for Media Foundation devices
3. Use first available type with devices

### Manual Selection
```bash
# Force Media Foundation
ndi-bridge.exe --capture-type mf

# Force DeckLink
ndi-bridge.exe --capture-type decklink

# Auto-detect (default)
ndi-bridge.exe --capture-type auto
```

## Adding New Capture Types

1. Create directory: `src/[platform]/[capture_type]/`
2. Implement `ICaptureDevice` interface
3. Add to CMakeLists.txt with optional flag
4. Update main.cpp device factory
5. Add documentation

## Performance Considerations

- All capture devices output UYVY format for NDI
- Format conversion happens in capture implementation
- Zero-copy where possible
- Dedicated capture thread per device
