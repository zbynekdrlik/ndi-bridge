// v4l2_capture.h
#pragma once

#include "../../common/capture_interface.h"
#include "v4l2_device_enumerator.h"
#include "v4l2_format_converter.h"
#include <memory>
#include <string>
#include <atomic>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <linux/videodev2.h>

namespace ndi_bridge {
namespace v4l2 {

/**
 * @brief V4L2 implementation of ICaptureDevice
 * 
 * Provides video capture functionality using Linux V4L2 API.
 * Supports USB capture cards and webcams with low latency optimization.
 * 
 * Version: 1.3.1
 */
class V4L2Capture : public ICaptureDevice {
public:
    V4L2Capture();
    ~V4L2Capture() override;
    
    // ICaptureDevice implementation
    std::vector<DeviceInfo> enumerateDevices() override;
    bool startCapture(const std::string& device_name = "") override;
    void stopCapture() override;
    bool isCapturing() const override;
    void setFrameCallback(FrameCallback callback) override;
    void setErrorCallback(ErrorCallback callback) override;
    bool hasError() const override;
    std::string getLastError() const override;
    
    // Performance statistics
    struct CaptureStats {
        uint64_t frames_captured = 0;
        uint64_t frames_dropped = 0;
        double total_latency_ms = 0.0;
        double total_convert_ms = 0.0;
        double max_latency_ms = 0.0;
        double min_latency_ms = 1000000.0;
        
        void reset() {
            frames_captured = 0;
            frames_dropped = 0;
            total_latency_ms = 0.0;
            total_convert_ms = 0.0;
            max_latency_ms = 0.0;
            min_latency_ms = 1000000.0;
        }
    };
    
    CaptureStats getStats() const;
    
private:
    // Buffer structure for memory-mapped buffers
    struct Buffer {
        void* start = nullptr;
        size_t length = 0;
    };
    
    // Supported format info
    struct SupportedFormat {
        uint32_t pixelformat;
        uint32_t width;
        uint32_t height;
        uint32_t fps;
    };
    
    // Initialize device by path
    bool initializeDevice(const std::string& device_path);
    
    // Shutdown current device
    void shutdownDevice();
    
    // Setup memory-mapped buffers
    bool setupBuffers();
    
    // Cleanup buffers
    void cleanupBuffers();
    
    // Start streaming
    bool startStreaming();
    
    // Stop streaming
    void stopStreaming();
    
    // Capture thread function
    void captureThread();
    
    // Process a captured frame (with pre-allocated buffer)
    void processFrame(const Buffer& buffer, const v4l2_buffer& v4l2_buf, 
                      std::vector<uint8_t>& bgra_buffer);
    
    // Set capture format
    bool setCaptureFormat(int width, int height, uint32_t pixelformat);
    
    // Find best format for device
    bool findBestFormat();
    
    // Enumerate all supported formats
    void enumerateFormats(std::vector<SupportedFormat>& formats);
    
    // Query device capabilities
    bool queryCapabilities();
    
    // Convert V4L2 format to our VideoFormat
    VideoFormat convertFormat(const v4l2_format& fmt) const;
    
    // Error handling
    void setError(const std::string& error);
    
private:
    // Device file descriptor
    int fd_;
    
    // Device path (e.g., "/dev/video0")
    std::string device_path_;
    
    // Device name
    std::string device_name_;
    
    // Memory-mapped buffers
    std::vector<Buffer> buffers_;
    
    // Current format
    v4l2_format current_format_;
    VideoFormat video_format_;
    
    // Format converter
    std::unique_ptr<V4L2FormatConverter> format_converter_;
    
    // Capture thread
    std::unique_ptr<std::thread> capture_thread_;
    std::atomic<bool> capturing_{false};
    std::atomic<bool> should_stop_{false};
    
    // Error state
    mutable std::mutex error_mutex_;
    std::string last_error_;
    std::atomic<bool> has_error_{false};
    
    // Callbacks with thread safety
    mutable std::mutex callback_mutex_;
    FrameCallback frame_callback_;
    ErrorCallback error_callback_;
    
    // Device capabilities
    v4l2_capability device_caps_;
    
    // Device mutex for thread safety
    mutable std::mutex device_mutex_;
    
    // Statistics
    mutable std::mutex stats_mutex_;
    CaptureStats stats_;
    
    // Disconnect detection
    uint32_t timeout_count_ = 0;
    
    // Buffer count (increase for better buffering)
    static constexpr unsigned int kBufferCount = 6;
};

} // namespace v4l2
} // namespace ndi_bridge
