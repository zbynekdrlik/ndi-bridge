#include "app_controller.h"
#include "logger.h"
#include "version.h"
#include <sstream>
#include <iomanip>

namespace ndi_bridge {

// Constants
constexpr int FRAME_QUEUE_WARNING_THRESHOLD = 10;
constexpr auto ERROR_COOLDOWN_PERIOD = std::chrono::seconds(1);

// FourCC codes for pixel formats
constexpr uint32_t FOURCC_UYVY = 0x59565955;  // 'UYVY'
constexpr uint32_t FOURCC_YUY2 = 0x32595559;  // 'YUY2'
constexpr uint32_t FOURCC_YUYV = 0x56595559;  // 'YUYV' - same as YUY2
constexpr uint32_t FOURCC_NV12 = 0x3231564E;  // 'NV12'
constexpr uint32_t FOURCC_BGRA = 0x41524742;  // 'BGRA'
constexpr uint32_t FOURCC_BGRX = 0x58524742;  // 'BGRX'

AppController::AppController(const Config& config)
    : config_(config) {
    Logger::info("Application Controller initialized");
    
    if (config_.verbose) {
        Logger::setVerbose(true);
        Logger::debug("Configuration:");
        Logger::debug("  Device: " + (config_.device_name.empty() ? "default" : config_.device_name));
        Logger::debug("  NDI Name: " + config_.ndi_name);
        Logger::debug("  Auto Retry: " + std::string(config_.auto_retry ? "enabled" : "disabled"));
        if (config_.auto_retry) {
            Logger::debug("  Retry Delay: " + std::to_string(config_.retry_delay_ms) + "ms");
            Logger::debug("  Max Retries: " + (config_.max_retries < 0 ? "infinite" : std::to_string(config_.max_retries)));
        }
    }
}

AppController::~AppController() {
    stop();
}

void AppController::setCaptureDevice(std::unique_ptr<ICaptureDevice> capture) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (running_) {
        reportError("Cannot set capture device while running", false);
        return;
    }
    
    capture_device_ = std::move(capture);
}

void AppController::setStatusCallback(StatusCallback callback) {
    std::lock_guard<std::mutex> lock(mutex_);
    status_callback_ = std::move(callback);
}

void AppController::setErrorCallback(ErrorCallback callback) {
    std::lock_guard<std::mutex> lock(mutex_);
    error_callback_ = std::move(callback);
}

bool AppController::start() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (running_) {
        reportError("Application already running", false);
        return false;
    }
    
    if (!capture_device_) {
        reportError("No capture device set", false);
        return false;
    }
    
    // Reset state
    stop_requested_ = false;
    restart_requested_ = false;
    retry_count_ = 0;
    frames_captured_ = 0;
    frames_sent_ = 0;
    frames_dropped_ = 0;
    
    // Set running flag BEFORE starting thread to avoid race condition
    running_ = true;
    
    // Start worker thread
    worker_thread_ = std::thread(&AppController::runLoop, this);
    
    // Wait a bit to ensure thread has started
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    
    return true;
}

void AppController::stop() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        
        if (!running_ && !worker_thread_.joinable()) {
            return;
        }
        
        stop_requested_ = true;
        cv_.notify_all();
    }
    
    // Wait for worker thread to finish
    if (worker_thread_.joinable()) {
        worker_thread_.join();
    }
}

std::string AppController::getCurrentDeviceName() const {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (!capture_device_) {
        return "none";
    }
    
    // Get device info from capture device
    auto devices = capture_device_->enumerateDevices();
    if (!devices.empty() && !devices[0].name.empty()) {
        return devices[0].name;
    }
    
    return config_.device_name.empty() ? "default" : config_.device_name;
}

void AppController::getFrameStats(uint64_t& captured_frames, 
                                 uint64_t& sent_frames,
                                 uint64_t& dropped_frames) const {
    captured_frames = frames_captured_;
    sent_frames = frames_sent_;
    dropped_frames = frames_dropped_;
}

int AppController::getNdiConnectionCount() const {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (!ndi_sender_) {
        return 0;
    }
    
    return ndi_sender_->getConnectionCount();
}

bool AppController::requestRestart() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (!running_) {
        return false;
    }
    
    restart_requested_ = true;
    cv_.notify_all();
    return true;
}

bool AppController::waitForCompletion(int timeout_ms) {
    std::unique_lock<std::mutex> lock(mutex_);
    
    if (!running_) {
        return true;
    }
    
    if (timeout_ms > 0) {
        return cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                           [this] { return !running_; });
    } else {
        cv_.wait(lock, [this] { return !running_; });
        return true;
    }
}

void AppController::runLoop() {
    // Note: running_ is already set to true in start() to avoid race condition
    reportStatus("Application started");
    
    while (!stop_requested_) {
        // Initialize components
        if (!initialize()) {
            if (!attemptRecovery()) {
                break;
            }
            continue;
        }
        
        // Reset retry count on successful initialization
        retry_count_ = 0;
        
        // Monitor capture status
        auto last_frame_check = std::chrono::steady_clock::now();
        auto last_frame_count = frames_captured_.load();
        
        // Run until error or restart requested
        while (!stop_requested_ && !restart_requested_) {
            std::unique_lock<std::mutex> lock(mutex_);
            
            // Wait for condition or timeout every second to check capture health
            cv_.wait_for(lock, std::chrono::seconds(1), [this] { 
                return stop_requested_ || restart_requested_ || 
                       (capture_device_ && capture_device_->hasError());
            });
            
            // Check if capture is still producing frames
            auto now = std::chrono::steady_clock::now();
            auto current_frame_count = frames_captured_.load();
            
            if (std::chrono::duration_cast<std::chrono::seconds>(now - last_frame_check).count() >= 5) {
                // Check if we're getting frames
                if (current_frame_count == last_frame_count && capture_device_->isCapturing()) {
                    // No frames in 5 seconds while supposedly capturing
                    lock.unlock();
                    reportError("No frames received for 5 seconds", true);
                    restart_requested_ = true;
                    break;
                }
                last_frame_check = now;
                last_frame_count = current_frame_count;
            }
            
            // Check why we woke up
            if (stop_requested_) {
                break;
            }
            
            if (restart_requested_) {
                lock.unlock();
                reportStatus("Restarting capture pipeline");
                break;
            }
            
            if (capture_device_ && capture_device_->hasError()) {
                lock.unlock();
                reportError("Capture device error detected", true);
                break;
            }
        }
        
        if (stop_requested_) {
            break;
        }
        
        // Shutdown for restart or error recovery
        shutdown();
        
        // Add delay before restart if it was an error
        if ((restart_requested_ || (capture_device_ && capture_device_->hasError())) && config_.retry_delay_ms > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(config_.retry_delay_ms));
        }
        
        restart_requested_ = false;
    }
    
    shutdown();
    running_ = false;
    reportStatus("Application stopped");
}

bool AppController::initialize() {
    reportStatus("Initializing components");
    
    // Create NDI sender
    ndi_sender_ = std::make_unique<NdiSender>(
        config_.ndi_name,
        [this](const std::string& error) { onNdiError(error); }
    );
    
    if (!ndi_sender_->initialize()) {
        reportError("Failed to initialize NDI sender", false);
        return false;
    }
    
    // v1.6.3: Set capture callbacks BEFORE starting capture
    // This ensures the callbacks are ready when frames start arriving
    capture_device_->setFrameCallback(
        [this](const void* data, size_t size, int64_t timestamp, 
               const ICaptureDevice::VideoFormat& format) {
            onFrameReceived(data, size, timestamp, format);
        }
    );
    
    capture_device_->setErrorCallback(
        [this](const std::string& error) { onCaptureError(error); }
    );
    
    // Start capture AFTER callbacks are set
    if (!capture_device_->startCapture(config_.device_name)) {
        reportError("Failed to start capture device", false);
        return false;
    }
    
    reportStatus("All components initialized successfully");
    return true;
}

void AppController::shutdown() {
    reportStatus("Shutting down components");
    
    // Stop capture first
    if (capture_device_) {
        capture_device_->stopCapture();
    }
    
    // Then shutdown NDI
    if (ndi_sender_) {
        ndi_sender_->shutdown();
        ndi_sender_.reset();
    }
    
    reportStatus("Components shut down");
}

void AppController::onFrameReceived(const void* frame_data, size_t frame_size,
                                   int64_t timestamp, const ICaptureDevice::VideoFormat& format) {
    frames_captured_++;
    
    if (!ndi_sender_ || !ndi_sender_->isReady()) {
        frames_dropped_++;
        return;
    }
    
    // Prepare frame info for NDI
    NdiSender::FrameInfo frame_info;
    frame_info.data = frame_data;
    frame_info.width = format.width;
    frame_info.height = format.height;
    frame_info.stride = format.stride;
    frame_info.fourcc = getFourCC(format);
    frame_info.timestamp_ns = timestamp;
    frame_info.fps_numerator = format.fps_numerator;    // Pass frame rate to NDI
    frame_info.fps_denominator = format.fps_denominator;  // Pass frame rate to NDI
    
    // Send frame
    if (ndi_sender_->sendFrame(frame_info)) {
        frames_sent_++;
    } else {
        frames_dropped_++;
    }
    
    // Log statistics periodically
    if (config_.verbose && frames_captured_ % 300 == 0) {  // Every 10 seconds at 30fps
        std::stringstream ss;
        ss << "Frame stats - Captured: " << frames_captured_
           << ", Sent: " << frames_sent_
           << ", Dropped: " << frames_dropped_
           << " (" << std::fixed << std::setprecision(1)
           << (frames_dropped_ * 100.0 / frames_captured_) << "%)";
        reportStatus(ss.str());
    }
}

void AppController::onCaptureError(const std::string& error) {
    reportError("Capture error: " + error, true);
    restart_requested_ = true;
    cv_.notify_all();
}

void AppController::onNdiError(const std::string& error) {
    reportError("NDI error: " + error, true);
    restart_requested_ = true;
    cv_.notify_all();
}

void AppController::reportStatus(const std::string& status) {
    Logger::info(status);
    
    std::lock_guard<std::mutex> lock(mutex_);
    if (status_callback_) {
        status_callback_(status);
    }
}

void AppController::reportError(const std::string& error, bool recoverable) {
    auto now = std::chrono::steady_clock::now();
    
    // Rate limit error messages
    if (error == last_error_message_ && 
        now - last_error_time_ < ERROR_COOLDOWN_PERIOD) {
        return;
    }
    
    last_error_message_ = error;
    last_error_time_ = now;
    
    Logger::error(error);
    
    std::lock_guard<std::mutex> lock(mutex_);
    if (error_callback_) {
        error_callback_(error, recoverable);
    }
}

bool AppController::attemptRecovery() {
    if (!config_.auto_retry) {
        reportError("Auto-retry disabled, stopping", false);
        return false;
    }
    
    retry_count_++;
    
    if (config_.max_retries >= 0 && retry_count_ > config_.max_retries) {
        reportError("Max retries exceeded, stopping", false);
        return false;
    }
    
    std::stringstream ss;
    ss << "Attempting recovery (retry " << retry_count_;
    if (config_.max_retries >= 0) {
        ss << "/" << config_.max_retries;
    }
    ss << ")";
    reportStatus(ss.str());
    
    // Wait before retry
    std::this_thread::sleep_for(std::chrono::milliseconds(config_.retry_delay_ms));
    
    return !stop_requested_;
}

uint32_t AppController::getFourCC(const ICaptureDevice::VideoFormat& format) const {
    // Map common format names to FourCC codes
    if (format.pixel_format == "UYVY" || format.pixel_format == "UYVY") {
        return FOURCC_UYVY;
    } else if (format.pixel_format == "YUY2" || format.pixel_format == "YUYV") {
        return FOURCC_YUYV;  // YUYV will be converted to UYVY in NDI sender
    } else if (format.pixel_format == "NV12") {
        return FOURCC_NV12;
    } else if (format.pixel_format == "BGRA") {
        return FOURCC_BGRA;
    } else if (format.pixel_format == "BGRX" || format.pixel_format == "BGR0") {
        return FOURCC_BGRX;
    }
    
    // Default to UYVY
    return FOURCC_UYVY;
}

} // namespace ndi_bridge
