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
 * Supports USB capture cards and webcams.
 * 
 * Version: 1.3.0
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
    
private:
    // Buffer structure for memory-mapped buffers
    struct Buffer {
        void* start;
        size_t length;
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
    
    // Process a captured frame
    void processFrame(const Buffer& buffer, const v4l2_buffer& v4l2_buf);
    
    // Set capture format
    bool setCaptureFormat(int width, int height, uint32_t pixelformat);
    
    // Find best format for device
    bool findBestFormat();
    
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
    
    // Callbacks
    FrameCallback frame_callback_;
    ErrorCallback error_callback_;
    
    // Device capabilities
    v4l2_capability device_caps_;
    
    // Buffer count
    static constexpr unsigned int kBufferCount = 4;
};

} // namespace v4l2
} // namespace ndi_bridge
