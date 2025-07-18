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
 * @brief V4L2 implementation of ICaptureDevice with optimized latency
 * 
 * Provides video capture functionality using Linux V4L2 API.
 * Supports USB capture cards and webcams with low latency optimization.
 * 
 * Version: 1.8.0 - Ultra-low latency with zero-copy YUV support
 * - Direct YUYV/UYVY pass-through without conversion
 * - Real-time scheduling support
 * - Ultra-low buffer counts (3 minimum)
 * - DMABUF preparation for future zero-copy
 * - Format priority favoring NDI-native formats
 * 
 * Pipeline structure (multi-threaded):
 * - Thread 1 (Capture): poll -> dequeue -> push to queue1 -> requeue
 * - Thread 2 (Convert): pop from queue1 -> convert -> push to queue2  
 * - Thread 3 (Send): pop from queue2 -> callback to NDI sender
 * 
 * Single-threaded mode:
 * - One thread: poll -> dequeue -> convert/send -> requeue
 * 
 * Zero-copy mode (YUV formats):
 * - One thread: poll -> dequeue -> direct send -> requeue
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
     * When disabled, uses single-threaded operation for lowest latency
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
        
        // End-to-end latency tracking
        double avg_e2e_latency_ms = 0.0;
        double max_e2e_latency_ms = 0.0;
        uint64_t e2e_samples = 0;
        
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
            avg_e2e_latency_ms = 0.0;
            max_e2e_latency_ms = 0.0;
            e2e_samples = 0;
        }
    };
    
    CaptureStats getStats() const;
    
    /**
     * @brief Set low latency mode
     * @param enable True to enable aggressive low latency settings
     * 
     * When enabled:
     * - Reduces buffer count to minimum (4)
     * - Uses immediate polling (no timeout)
     * - Minimizes queue depths
     * - Forces single-threaded mode
     */
    void setLowLatencyMode(bool enable);
    bool isLowLatencyMode() const { return low_latency_mode_; }
    
    /**
     * @brief Enable ultra-low latency mode
     * @param enable True to enable most aggressive settings
     * 
     * When enabled:
     * - Minimum buffer count (3)
     * - Zero-copy for YUV formats
     * - Single-threaded
     * - Immediate polling
     */
    void setUltraLowLatencyMode(bool enable);
    bool isUltraLowLatencyMode() const { return ultra_low_latency_mode_; }
    
    /**
     * @brief Enable real-time scheduling
     * @param enable True to enable
     * @param priority RT priority (1-99)
     */
    void setRealtimeScheduling(bool enable, int priority = 50);
    
    /**
     * @brief Enable zero-copy mode
     * @param enable True to enable direct format pass-through
     */
    void setZeroCopyMode(bool enable) { zero_copy_mode_ = enable; }
    bool isZeroCopyMode() const { return zero_copy_mode_; }
    
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
    
    // Try to setup DMABUF for zero-copy
    bool trySetupDMABUF();
    
    // Cleanup buffers
    void cleanupBuffers();
    
    // Start streaming
    bool startStreaming();
    
    // Stop streaming
    void stopStreaming();
    
    // Single-threaded capture function (optimized for low latency)
    void captureThreadSingle();
    
    // Multi-threaded pipeline functions
    void captureThreadMulti();     // Thread 1: Capture
    void convertThreadMulti();     // Thread 2: Convert
    void sendThreadMulti();        // Thread 3: Send
    
    // Process a captured frame (single-threaded version)
    void processFrame(const Buffer& buffer, const v4l2_buffer& v4l2_buf, 
                      std::vector<uint8_t>& bgra_buffer);
    
    // Direct send without conversion (zero-copy path)
    void sendFrameDirect(const Buffer& buffer, const v4l2_buffer& v4l2_buf);
    
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
    
    // Apply real-time scheduling to thread
    void applyRealtimeScheduling();
    
    // Convert pixel format to string
    std::string pixelFormatToString(uint32_t format) const;
    
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
    
    // Zero-copy optimization
    bool zero_copy_mode_{false};
    bool zero_copy_logged_{false};
    bool dmabuf_supported_{false};
    v4l2_memory buffer_type_{V4L2_MEMORY_MMAP};
    
    // Real-time scheduling
    bool realtime_scheduling_{false};
    int realtime_priority_{50};
    
    // Latency modes
    bool low_latency_mode_{false};
    bool ultra_low_latency_mode_{false};
    
    // Buffer count - optimized for low latency
    static constexpr unsigned int kBufferCountNormal = 6;        // Reduced from 10
    static constexpr unsigned int kBufferCountLowLatency = 4;    // Minimum for stability
    static constexpr unsigned int kBufferCountUltraLow = 3;      // Absolute minimum
    
    // Queue depths for multi-threading - optimized for low latency
    static constexpr size_t kCaptureQueueDepthNormal = 3;        // Reduced from 5
    static constexpr size_t kCaptureQueueDepthLowLatency = 2;
    static constexpr size_t kConvertQueueDepthNormal = 2;        // Reduced from 5
    static constexpr size_t kConvertQueueDepthLowLatency = 1;
    static constexpr size_t kQueueDepthUltraLow = 1;             // Single buffer queue
    
    // Poll timeouts - optimized for low latency
    static constexpr int kPollTimeoutMsMulti = 0;          // Immediate (was 1ms)
    static constexpr int kPollTimeoutMsSingle = 1;         // Reduced from 5ms
    static constexpr int kPollTimeoutMsLowLatency = 0;     // Immediate
    static constexpr int kPollTimeoutUltraLow = 0;         // No wait
    
    // Format priority for NDI optimization
    static const std::vector<uint32_t> kFormatPriority;
    
    // Get current buffer count based on mode
    unsigned int getBufferCount() const {
        if (ultra_low_latency_mode_) return kBufferCountUltraLow;
        return low_latency_mode_ ? kBufferCountLowLatency : kBufferCountNormal;
    }
    
    // Get current queue depths based on mode
    size_t getCaptureQueueDepth() const {
        if (ultra_low_latency_mode_) return kQueueDepthUltraLow;
        return low_latency_mode_ ? kCaptureQueueDepthLowLatency : kCaptureQueueDepthNormal;
    }
    
    size_t getConvertQueueDepth() const {
        if (ultra_low_latency_mode_) return kQueueDepthUltraLow;
        return low_latency_mode_ ? kConvertQueueDepthLowLatency : kConvertQueueDepthNormal;
    }
    
    // Get poll timeout based on mode
    int getPollTimeout() const {
        if (ultra_low_latency_mode_) return kPollTimeoutUltraLow;
        if (low_latency_mode_) return kPollTimeoutMsLowLatency;
        return use_multi_threading_ ? kPollTimeoutMsMulti : kPollTimeoutMsSingle;
    }
};

} // namespace v4l2
} // namespace ndi_bridge
