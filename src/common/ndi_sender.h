#pragma once

#include <string>
#include <memory>
#include <cstdint>
#include <mutex>
#include <atomic>
#include <functional>
#include <vector>

// Forward declare NDI types to avoid including NDI SDK headers here
struct NDIlib_send_instance_type;
typedef NDIlib_send_instance_type* NDIlib_send_instance_t;

namespace ndi_bridge {

/**
 * @brief NDI sender wrapper for sending video frames
 * 
 * This class provides a clean interface to the NDI SDK for sending video frames.
 * It handles NDI library initialization, sender creation, and frame sending with
 * proper format handling.
 * 
 * Version: 1.4.0 - Added zero-copy YUYV support with AVX2 optimization
 */
class NdiSender {
public:
    /**
     * @brief Frame format information
     */
    struct FrameInfo {
        const void* data;
        uint32_t width;
        uint32_t height;
        uint32_t stride;
        uint32_t fourcc;  // FourCC code for pixel format
        int64_t timestamp_ns;  // Timestamp in nanoseconds
        uint32_t fps_numerator;  // Frame rate numerator
        uint32_t fps_denominator;  // Frame rate denominator
    };

    /**
     * @brief Callback for error notifications
     */
    using ErrorCallback = std::function<void(const std::string& error)>;

    /**
     * @brief Constructor
     * @param sender_name Name to broadcast for this NDI sender
     * @param error_callback Optional callback for error notifications
     */
    explicit NdiSender(const std::string& sender_name, 
                      ErrorCallback error_callback = nullptr);
    
    /**
     * @brief Destructor - ensures clean shutdown
     */
    ~NdiSender();

    // Disable copy operations
    NdiSender(const NdiSender&) = delete;
    NdiSender& operator=(const NdiSender&) = delete;

    // Enable move operations
    NdiSender(NdiSender&& other) noexcept;
    NdiSender& operator=(NdiSender&& other) noexcept;

    /**
     * @brief Initialize the NDI sender
     * @return true if successful, false otherwise
     */
    bool initialize();

    /**
     * @brief Shutdown the NDI sender
     */
    void shutdown();

    /**
     * @brief Send a video frame
     * @param frame Frame information including data and format
     * @return true if frame was sent successfully
     * 
     * Note: YUYV format will be automatically converted to UYVY
     * using optimized AVX2 instructions when available.
     */
    bool sendFrame(const FrameInfo& frame);

    /**
     * @brief Check if the sender is initialized and ready
     * @return true if ready to send frames
     */
    bool isReady() const;

    /**
     * @brief Get the current sender name
     * @return The NDI sender name being broadcast
     */
    const std::string& getSenderName() const { return sender_name_; }

    /**
     * @brief Get the number of current connections
     * @return Number of receivers connected to this sender
     */
    int getConnectionCount() const;

    /**
     * @brief Get total frames sent
     * @return Total number of frames sent since initialization
     */
    uint64_t getFramesSent() const { return frames_sent_; }

    /**
     * @brief Check if NDI runtime is available
     * @return true if NDI runtime is installed and available
     */
    static bool isNdiAvailable();

    /**
     * @brief Get NDI runtime version
     * @return Version string of the NDI runtime
     */
    static std::string getNdiVersion();

private:
    /**
     * @brief Load NDI library dynamically
     * @return true if library loaded successfully
     */
    bool loadNdiLibrary();

    /**
     * @brief Create the NDI sender instance
     * @return true if sender created successfully
     */
    bool createSender();

    /**
     * @brief Cleanup all NDI resources
     */
    void cleanup();

    /**
     * @brief Report an error through the callback
     * @param error Error message
     */
    void reportError(const std::string& error);

    /**
     * @brief Convert YUYV to UYVY format (scalar version)
     */
    void convertYUYVtoUYVY_Scalar(const uint8_t* src, uint8_t* dst, int width, int height);

    /**
     * @brief Convert YUYV to UYVY format (AVX2 optimized version)
     */
    void convertYUYVtoUYVY_AVX2(const uint8_t* src, uint8_t* dst, int width, int height);

    // Member variables
    std::string sender_name_;
    ErrorCallback error_callback_;
    mutable std::mutex mutex_;
    std::atomic<bool> initialized_{false};
    std::atomic<uint64_t> frames_sent_{0};
    
    // NDI handles
    NDIlib_send_instance_t ndi_send_instance_{nullptr};
    
    // Optimization support
    bool has_avx2_{false};
    bool yuyv_conversion_logged_{false};
    std::vector<uint8_t> yuyv_to_uyvy_buffer_;
    
    // NDI library management
    static std::mutex lib_mutex_;
    static int lib_ref_count_;
};

} // namespace ndi_bridge
