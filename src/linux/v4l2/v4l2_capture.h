// v4l2_capture.h
#pragma once

#include "../../common/capture_interface.h"
#include "../../common/frame_queue.h"
#include "../../common/pipeline_thread_pool.h"
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
 * @brief V4L2 implementation of ICaptureDevice with multi-threaded pipeline
 * 
 * Provides video capture functionality using Linux V4L2 API.
 * Supports USB capture cards and webcams with low latency optimization.
 * 
 * Version: 1.5.0 - Added multi-threaded pipeline architecture
 * 
 * Pipeline structure:
 * - Thread 1 (Capture): poll -> dequeue -> push to queue1 -> requeue
 * - Thread 2 (Convert): pop from queue1 -> convert -> push to queue2  
 * - Thread 3 (Send): pop from queue2 -> callback to NDI sender
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
    
    /**
     * @brief Enable/disable multi-threaded pipeline
     * @param enable True to enable multi-threading (default: true)
     * 
     * When disabled, falls back to single-threaded operation
     */
    void setMultiThreadingEnabled(bool enable) { use_multi_threading_ = enable; }
    bool isMultiThreadingEnabled() const { return use_multi_threading_; }
    
    // Performance statistics
    struct CaptureStats {
        uint64_t frames_captured = 0;
        uint64_t frames_dropped = 0;
        uint64_t zero_copy_frames = 0;  // Frames sent without conversion
        double total_latency_ms = 0.0;
        double total_convert_ms = 0.0;
        double max_latency_ms = 0.0;
        double min_latency_ms = 1000000.0;
        
        // Multi-threading specific stats
        uint64_t queue1_drops = 0;  // Drops between capture and convert
        uint64_t queue2_drops = 0;  // Drops between convert and send
        double avg_capture_time_ms = 0.0;
        double avg_convert_time_ms = 0.0;
        double avg_send_time_ms = 0.0;
        
        void reset() {
            frames_captured = 0;
            frames_dropped = 0;
            zero_copy_frames = 0;
            total_latency_ms = 0.0;
            total_convert_ms = 0.0;
            max_latency_ms = 0.0;
            min_latency_ms = 1000000.0;
            queue1_drops = 0;
            queue2_drops = 0;
            avg_capture_time_ms = 0.0;
            avg_convert_time_ms = 0.0;
            avg_send_time_ms = 0.0;
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
    
    // Single-threaded capture function (legacy)
    void captureThreadSingle();
    
    // Multi-threaded pipeline functions
    void captureThreadMulti();     // Thread 1: Capture
    void convertThreadMulti();     // Thread 2: Convert
    void sendThreadMulti();        // Thread 3: Send
    
    // Process a captured frame (single-threaded version)
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
    
    // Multi-threading support
    bool use_multi_threading_{true};
    std::unique_ptr<PipelineThreadPool> thread_pool_;
    
    // Frame queues for multi-threaded pipeline
    std::unique_ptr<FrameQueue> capture_to_convert_queue_;  // Queue 1
    std::unique_ptr<FrameQueue> convert_to_send_queue_;     // Queue 2
    std::unique_ptr<BufferIndexQueue> requeue_queue_;       // For buffer recycling
    
    // Thread IDs
    size_t capture_thread_id_{0};
    size_t convert_thread_id_{0};
    size_t send_thread_id_{0};
    
    // Legacy single-threaded capture
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
    
    // Zero-copy optimization flag
    bool zero_copy_logged_{false};
    
    // Buffer count optimized for Intel N100 (10 buffers for smoother operation)
    static constexpr unsigned int kBufferCount = 10;
    
    // Queue depths for multi-threading
    static constexpr size_t kCaptureQueueDepth = 5;
    static constexpr size_t kConvertQueueDepth = 5;
};

} // namespace v4l2
} // namespace ndi_bridge
