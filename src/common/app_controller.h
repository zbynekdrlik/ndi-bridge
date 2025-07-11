#pragma once

#include <memory>
#include <string>
#include <atomic>
#include <thread>
#include <functional>
#include <mutex>
#include <condition_variable>
#include <chrono>

#include "capture_interface.h"
#include "ndi_sender.h"

namespace ndi_bridge {

/**
 * @brief Application controller that coordinates capture and NDI sending
 * 
 * This class manages the overall application lifecycle, coordinating between
 * the capture device and NDI sender. It handles initialization, error recovery,
 * and graceful shutdown.
 * 
 * Version: 1.0.0
 */
class AppController {
public:
    /**
     * @brief Configuration for the application
     */
    struct Config {
        std::string device_name;      // Capture device name (empty for default)
        std::string ndi_name;         // NDI sender name
        bool auto_retry = true;       // Auto-retry on errors
        int retry_delay_ms = 5000;    // Delay between retries
        int max_retries = -1;         // Max retries (-1 for infinite)
        bool verbose = false;         // Verbose logging
    };

    /**
     * @brief Status callback for application state changes
     */
    using StatusCallback = std::function<void(const std::string& status)>;

    /**
     * @brief Error callback for error notifications
     */
    using ErrorCallback = std::function<void(const std::string& error, bool recoverable)>;

    /**
     * @brief Constructor
     * @param config Application configuration
     */
    explicit AppController(const Config& config);

    /**
     * @brief Destructor
     */
    ~AppController();

    // Disable copy operations
    AppController(const AppController&) = delete;
    AppController& operator=(const AppController&) = delete;

    /**
     * @brief Set the capture device implementation
     * @param capture The capture device to use
     */
    void setCaptureDevice(std::unique_ptr<ICaptureDevice> capture);

    /**
     * @brief Set status callback
     * @param callback Callback for status updates
     */
    void setStatusCallback(StatusCallback callback);

    /**
     * @brief Set error callback
     * @param callback Callback for error notifications
     */
    void setErrorCallback(ErrorCallback callback);

    /**
     * @brief Start the application
     * @return true if started successfully
     */
    bool start();

    /**
     * @brief Stop the application
     */
    void stop();

    /**
     * @brief Check if the application is running
     * @return true if running
     */
    bool isRunning() const { return running_; }

    /**
     * @brief Get current device name
     * @return Device name or "default" if using default device
     */
    std::string getCurrentDeviceName() const;

    /**
     * @brief Get frame statistics
     * @param captured_frames Number of frames captured
     * @param sent_frames Number of frames sent via NDI
     * @param dropped_frames Number of frames dropped
     */
    void getFrameStats(uint64_t& captured_frames, 
                      uint64_t& sent_frames,
                      uint64_t& dropped_frames) const;

    /**
     * @brief Get NDI connection count
     * @return Number of NDI connections
     */
    int getNdiConnectionCount() const;

    /**
     * @brief Request a restart of the capture/NDI pipeline
     * @return true if restart initiated
     */
    bool requestRestart();

    /**
     * @brief Wait for the application to finish
     * @param timeout_ms Timeout in milliseconds (0 for infinite)
     * @return true if finished, false if timeout
     */
    bool waitForCompletion(int timeout_ms = 0);

private:
    /**
     * @brief Initialize all components
     * @return true if successful
     */
    bool initialize();

    /**
     * @brief Shutdown all components
     */
    void shutdown();

    /**
     * @brief Run the main application loop
     */
    void runLoop();

    /**
     * @brief Handle frame from capture device
     * @param frame_data Frame data
     * @param frame_size Frame size in bytes
     * @param timestamp Timestamp
     * @param format Frame format
     */
    void onFrameReceived(const void* frame_data, size_t frame_size,
                        int64_t timestamp, const ICaptureDevice::VideoFormat& format);

    /**
     * @brief Handle capture error
     * @param error Error message
     */
    void onCaptureError(const std::string& error);

    /**
     * @brief Handle NDI error
     * @param error Error message
     */
    void onNdiError(const std::string& error);

    /**
     * @brief Report status change
     * @param status Status message
     */
    void reportStatus(const std::string& status);

    /**
     * @brief Report error
     * @param error Error message
     * @param recoverable Whether error is recoverable
     */
    void reportError(const std::string& error, bool recoverable);

    /**
     * @brief Attempt to recover from error
     * @return true if recovery successful
     */
    bool attemptRecovery();

    /**
     * @brief Get FourCC code from format
     * @param format Video format
     * @return FourCC code for NDI
     */
    uint32_t getFourCC(const ICaptureDevice::VideoFormat& format) const;

    // Configuration
    Config config_;
    
    // Callbacks
    StatusCallback status_callback_;
    ErrorCallback error_callback_;
    
    // Components
    std::unique_ptr<ICaptureDevice> capture_device_;
    std::unique_ptr<NdiSender> ndi_sender_;
    
    // State
    std::atomic<bool> running_{false};
    std::atomic<bool> stop_requested_{false};
    std::atomic<bool> restart_requested_{false};
    std::atomic<int> retry_count_{0};
    
    // Statistics
    std::atomic<uint64_t> frames_captured_{0};
    std::atomic<uint64_t> frames_sent_{0};
    std::atomic<uint64_t> frames_dropped_{0};
    
    // Threading
    std::thread worker_thread_;
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    
    // Error handling
    std::chrono::steady_clock::time_point last_error_time_;
    std::string last_error_message_;
};

} // namespace ndi_bridge
