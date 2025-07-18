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
#include <vector>
#include <linux/videodev2.h>

namespace ndi_bridge {
namespace v4l2 {

/**
 * @brief V4L2 implementation of ICaptureDevice - ZERO COMPROMISE VERSION
 * 
 * Version: 2.0.0 - Ultra-low latency single-purpose appliance
 * - ALWAYS 3 buffers (absolute minimum)
 * - ALWAYS zero-copy for YUV formats
 * - ALWAYS single-threaded
 * - ALWAYS real-time priority 80
 * - ALWAYS immediate polling (0ms)
 * - NO configuration options
 * - NO compromise on latency
 * 
 * This is an APPLIANCE, not an application.
 */
class V4L2Capture : public ICaptureDevice {
public:
    V4L2Capture();
    ~V4L2Capture() override;
    
    // ICaptureDevice implementation ONLY
    std::vector<DeviceInfo> enumerateDevices() override;
    bool startCapture(const std::string& device_name = "") override;
    void stopCapture() override;
    bool isCapturing() const override;
    void setFrameCallback(FrameCallback callback) override;
    void setErrorCallback(ErrorCallback callback) override;
    bool hasError() const override;
    std::string getLastError() const override;
    
    // NO PUBLIC CONFIGURATION METHODS!
    
private:
    // HARDCODED OPTIMAL SETTINGS
    static constexpr unsigned int kBufferCount = 3;          // Absolute minimum
    static constexpr int kPollTimeout = 0;                   // No wait
    static constexpr bool kUseMultiThreading = false;        // Single thread only
    static constexpr bool kZeroCopyMode = true;              // Always zero-copy
    static constexpr int kRealtimePriority = 80;             // High RT priority
    
    // Buffer structure
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
    
    // Initialize device
    bool initializeDevice(const std::string& device_path);
    
    // Shutdown device
    void shutdownDevice();
    
    // Setup buffers
    bool setupBuffers();
    
    // Cleanup buffers
    void cleanupBuffers();
    
    // Start streaming
    bool startStreaming();
    
    // Stop streaming
    void stopStreaming();
    
    // Main capture thread - single-threaded ultra-low latency
    void captureThreadSingle();
    
    // Direct send without conversion (zero-copy path)
    void sendFrameDirect(const Buffer& buffer, const v4l2_buffer& v4l2_buf);
    
    // Process frame with conversion
    void processFrame(const Buffer& buffer, const v4l2_buffer& v4l2_buf, 
                      std::vector<uint8_t>& bgra_buffer);
    
    // Set capture format
    bool setCaptureFormat(int width, int height, uint32_t pixelformat);
    
    // Find best format
    bool findBestFormat();
    
    // Enumerate formats
    void enumerateFormats(std::vector<SupportedFormat>& formats);
    
    // Query capabilities
    bool queryCapabilities();
    
    // Convert format
    VideoFormat convertFormat(const v4l2_format& fmt) const;
    
    // Apply real-time scheduling
    void applyRealtimeScheduling();
    
    // Convert pixel format to string
    std::string pixelFormatToString(uint32_t format) const;
    
    // Error handling
    void setError(const std::string& error);
    
private:
    // Device file descriptor
    int fd_;
    
    // Device path
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
    
    // Single capture thread
    std::unique_ptr<std::thread> capture_thread_;
    std::atomic<bool> capturing_{false};
    std::atomic<bool> should_stop_{false};
    
    // Error state
    mutable std::mutex error_mutex_;
    std::string last_error_;
    std::atomic<bool> has_error_{false};
    
    // Callbacks
    mutable std::mutex callback_mutex_;
    FrameCallback frame_callback_;
    ErrorCallback error_callback_;
    
    // Device capabilities
    v4l2_capability device_caps_;
    
    // Device mutex
    mutable std::mutex device_mutex_;
    
    // Statistics (minimal)
    std::atomic<uint64_t> frames_captured_{0};
    std::atomic<uint64_t> frames_dropped_{0};
    std::atomic<uint64_t> zero_copy_frames_{0};
    
    // Disconnect detection
    uint32_t timeout_count_ = 0;
    
    // Zero-copy state
    bool zero_copy_logged_{false};
    
    // Format priority for NDI optimization
    static const std::vector<uint32_t> kFormatPriority;
    
    // ALWAYS use these values
    unsigned int getBufferCount() const { return kBufferCount; }
    int getPollTimeout() const { return kPollTimeout; }
    bool isMultiThreadingEnabled() const { return kUseMultiThreading; }
    bool isZeroCopyMode() const { return kZeroCopyMode; }
    int getRealtimePriority() const { return kRealtimePriority; }
};

} // namespace v4l2
} // namespace ndi_bridge
