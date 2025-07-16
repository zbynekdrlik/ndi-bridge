// ICaptureDevice.h
#pragma once

#include <string>
#include <vector>
#include <memory>
#include <chrono>
#include <unordered_map>

// Forward declaration
struct FrameData {
    std::vector<uint8_t> data;
    int width = 0;
    int height = 0;
    int stride = 0;
    std::chrono::steady_clock::time_point timestamp;
    
    enum class FrameFormat {
        Unknown,
        BGRA,     // 32-bit BGRA
        RGB24,    // 24-bit RGB
        YUV420,   // YUV 4:2:0
        NV12,     // YUV 4:2:0 with interleaved UV
        UYVY      // YUV 4:2:2 packed
    } format = FrameFormat::Unknown;
};

struct CaptureStatistics {
    uint64_t capturedFrames = 0;
    uint64_t droppedFrames = 0;
    double currentFPS = 0.0;
    double averageFPS = 0.0;
    
    // v1.6.0: Added metadata field for extended statistics
    std::unordered_map<std::string, std::string> metadata;
};

// Abstract interface for all capture devices
class ICaptureDevice {
public:
    virtual ~ICaptureDevice() = default;
    
    // Initialize the device with a specific device name/identifier
    virtual bool Initialize(const std::string& deviceName) = 0;
    
    // Start capturing frames
    virtual bool StartCapture() = 0;
    
    // Stop capturing frames
    virtual void StopCapture() = 0;
    
    // Get the next available frame (blocks until available or timeout)
    virtual bool GetNextFrame(FrameData& frame) = 0;
    
    // Get device information
    virtual std::string GetDeviceName() const = 0;
    
    // Check if currently capturing
    virtual bool IsCapturing() const = 0;
    
    // Get supported capture formats
    virtual std::vector<std::string> GetSupportedFormats() const = 0;
    
    // Set capture format
    virtual bool SetFormat(const std::string& format) = 0;
    
    // Get capture statistics
    virtual void GetStatistics(CaptureStatistics& stats) const = 0;
};
