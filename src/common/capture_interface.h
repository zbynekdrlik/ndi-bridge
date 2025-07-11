// capture_interface.h
#pragma once

#include <windows.h>
#include <string>
#include <vector>
#include <memory>
#include <functional>

namespace ndi_bridge {

// Forward declarations
struct FrameData {
    const uint8_t* data;
    size_t size;
    int width;
    int height;
    uint32_t fourcc;
    uint32_t fps_numerator;
    uint32_t fps_denominator;
    bool is_interlaced;
    int64_t timestamp;
};

// Callback for frame delivery
using FrameCallback = std::function<void(const FrameData&)>;

// Abstract interface for video capture implementations
class ICaptureDevice {
public:
    virtual ~ICaptureDevice() = default;
    
    // Device enumeration
    virtual std::vector<std::pair<std::string, std::string>> EnumerateDevices() = 0;
    
    // Device selection and initialization
    virtual bool SelectDevice(const std::string& device_id) = 0;
    virtual bool Initialize() = 0;
    virtual void Shutdown() = 0;
    
    // Capture control
    virtual bool StartCapture(FrameCallback callback) = 0;
    virtual void StopCapture() = 0;
    virtual bool IsCapturing() const = 0;
    
    // Format configuration
    virtual bool SetOutputFormat(int width, int height, uint32_t fps_num, uint32_t fps_den) = 0;
    virtual void GetCurrentFormat(int& width, int& height, uint32_t& fps_num, uint32_t& fps_den, uint32_t& fourcc) = 0;
    
    // Device status
    virtual bool IsDeviceValid() const = 0;
    virtual std::string GetLastError() const = 0;
};

// Factory for creating capture devices
class CaptureDeviceFactory {
public:
    enum class CaptureType {
        MediaFoundation,
        DeckLink
    };
    
    static std::unique_ptr<ICaptureDevice> CreateDevice(CaptureType type);
};

} // namespace ndi_bridge
