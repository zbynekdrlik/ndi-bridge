// v4l2_capture.cpp
#include "v4l2_capture.h"
#include "../../common/logger.h"
#include "../../common/version.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <errno.h>
#include <cstring>
#include <sstream>
#include <chrono>
#include <poll.h>
#include <algorithm>
#include <sched.h>
#include <pthread.h>
#include <sys/poll.h>

namespace ndi_bridge {
namespace v4l2 {

// Format priority for NDI optimization
const std::vector<uint32_t> V4L2Capture::kFormatPriority = {
    V4L2_PIX_FMT_UYVY,    // NDI native - best
    V4L2_PIX_FMT_YUYV,    // Simple byte swap to UYVY
    V4L2_PIX_FMT_NV12,    // Requires conversion
    V4L2_PIX_FMT_MJPEG    // Avoid - needs decompression
};

V4L2Capture::V4L2Capture() 
    : fd_(-1)
    , buffer_type_(V4L2_MEMORY_MMAP)
    , dmabuf_supported_(false)
    , capturing_(false)
    , should_stop_(false)
    , has_error_(false)
    , use_multi_threading_(kUseMultiThreading)     // ALWAYS single thread
    , zero_copy_mode_(kZeroCopyMode)               // ALWAYS zero copy
    , realtime_scheduling_(true)                     // ALWAYS try RT
    , realtime_priority_(kRealtimePriority)         // ALWAYS high priority
    , low_latency_mode_(true)                        // ALWAYS low latency
    , ultra_low_latency_mode_(true)                  // ALWAYS ultra low
    , frames_captured_(0)
    , frames_dropped_(0)
    , zero_copy_frames_(0)
    , timeout_count_(0)
    , zero_copy_logged_(false) {
    
    Logger::info("V4L2 Optimized Low Latency Capture (v" NDI_BRIDGE_VERSION ")");
    Logger::info("Configuration: " + std::to_string(kBufferCount) + " buffers, zero-copy, single-thread, RT priority " + std::to_string(kRealtimePriority));
    Logger::info("Optimized for stable 60fps and 8-frame roundtrip latency");
    
    memset(&current_format_, 0, sizeof(current_format_));
    memset(&device_caps_, 0, sizeof(device_caps_));
}

V4L2Capture::~V4L2Capture() {
    stopCapture();
    Logger::info("V4L2Capture: Destroyed");
}

std::vector<ICaptureDevice::DeviceInfo> V4L2Capture::enumerateDevices() {
    std::vector<ICaptureDevice::DeviceInfo> devices;
    
    auto v4l2_devices = V4L2DeviceEnumerator::enumerateDevices();
    for (const auto& v4l2_dev : v4l2_devices) {
        if (v4l2_dev.supportsCapture() && v4l2_dev.supportsStreaming()) {
            ICaptureDevice::DeviceInfo info;
            info.id = v4l2_dev.path;
            info.name = v4l2_dev.name + " (" + v4l2_dev.bus_info + ")";
            devices.push_back(info);
        }
    }
    
    Logger::info("V4L2Capture: Found " + std::to_string(devices.size()) + " capture devices");
    return devices;
}

bool V4L2Capture::startCapture(const std::string& device_name) {
    std::lock_guard<std::mutex> lock(device_mutex_);
    
    if (isCapturing()) {
        Logger::warning("V4L2Capture: Already capturing");
        return true;
    }
    
    std::string device_path;
    
    if (device_name.empty()) {
        // Use first available device
        auto devices = enumerateDevices();
        if (devices.empty()) {
            setError("No V4L2 capture devices found");
            return false;
        }
        device_path = devices[0].id;
        device_name_ = devices[0].name;
    } else if (device_name.find("/dev/") == 0) {
        // Direct device path
        device_path = device_name;
        auto info = V4L2DeviceEnumerator::getDeviceInfo(device_path);
        device_name_ = info.name;
    } else {
        // Search by name
        device_path = V4L2DeviceEnumerator::findDeviceByName(device_name);
        if (device_path.empty()) {
            setError("Device not found: " + device_name);
            return false;
        }
        device_name_ = device_name;
    }
    
    Logger::info("V4L2Capture: Starting capture with device: " + device_path);
    
    // ALWAYS log our EXTREME settings
    Logger::info("Applying EXTREME PERFORMANCE settings:");
    Logger::info("  - Buffer count: " + std::to_string(kBufferCount) + " (absolute minimum)");
    Logger::info("  - Zero-copy: ENABLED");
    Logger::info("  - Threading: SINGLE");
    Logger::info("  - Polling: PURE BUSY-WAIT (100% CPU)");
    Logger::info("  - Real-time: SCHED_FIFO priority " + std::to_string(kRealtimePriority));
    Logger::info("  - CPU affinity: core " + std::to_string(kCpuAffinity));
    
    if (!initializeDevice(device_path)) {
        return false;
    }
    
    if (!queryCapabilities()) {
        shutdownDevice();
        return false;
    }
    
    if (!findBestFormat()) {
        shutdownDevice();
        return false;
    }
    
    if (!setupBuffers()) {
        shutdownDevice();
        return false;
    }
    
    if (!startStreaming()) {
        cleanupBuffers();
        shutdownDevice();
        return false;
    }
    
    // Reset statistics
    stats_.reset();
    
    // Clear any previous errors
    has_error_ = false;
    last_error_.clear();
    
    // ALWAYS start EXTREME capture thread
    should_stop_ = false;
    capturing_ = true;
    
    Logger::info("V4L2Capture: Starting optimized capture thread");
    capture_thread_ = std::make_unique<std::thread>(&V4L2Capture::captureThreadExtreme, this);
    
    Logger::info("V4L2Capture: Capture started successfully (optimized for 60fps)");
    return true;
}

void V4L2Capture::stopCapture() {
    std::lock_guard<std::mutex> lock(device_mutex_);
    
    if (!isCapturing()) {
        return;
    }
    
    Logger::info("V4L2Capture: Stopping capture");
    
    // Signal thread to stop
    should_stop_ = true;
    
    // Wait for thread to finish
    if (capture_thread_ && capture_thread_->joinable()) {
        capture_thread_->join();
    }
    capture_thread_.reset();
    
    capturing_ = false;
    
    // Log final statistics
    if (stats_.frames_captured > 0) {
        double avg_latency = stats_.total_latency_ms / stats_.frames_captured;
        Logger::info("V4L2Capture: Final stats - Frames: " + std::to_string(stats_.frames_captured) +
                   ", Avg latency: " + std::to_string(avg_latency) + "ms" +
                   ", Dropped: " + std::to_string(stats_.frames_dropped) + 
                   ", Zero-copy: " + std::to_string(stats_.zero_copy_frames));
        
        if (stats_.e2e_samples > 0) {
            Logger::info("V4L2Capture: E2E latency - Avg: " + 
                       std::to_string(stats_.avg_e2e_latency_ms) + "ms" +
                       ", Max: " + std::to_string(stats_.max_e2e_latency_ms) + "ms");
        }
    }
    
    // Stop streaming
    stopStreaming();
    
    // Cleanup
    cleanupBuffers();
    shutdownDevice();
    
    Logger::info("V4L2Capture: Capture stopped");
}

bool V4L2Capture::isCapturing() const {
    return capturing_.load();
}

void V4L2Capture::setFrameCallback(FrameCallback callback) {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    frame_callback_ = callback;
}

void V4L2Capture::setErrorCallback(ErrorCallback callback) {
    std::lock_guard<std::mutex> lock(callback_mutex_);
    error_callback_ = callback;
}

bool V4L2Capture::hasError() const {
    return has_error_.load();
}

std::string V4L2Capture::getLastError() const {
    std::lock_guard<std::mutex> lock(error_mutex_);
    return last_error_;
}

// NO CONFIGURATION METHODS - Everything is hardcoded for maximum performance

bool V4L2Capture::initializeDevice(const std::string& device_path) {
    device_path_ = device_path;
    
    // Open device
    fd_ = open(device_path.c_str(), O_RDWR | O_NONBLOCK);
    if (fd_ < 0) {
        setError("Failed to open device " + device_path + ": " + strerror(errno));
        return false;
    }
    
    // Small delay to ensure USB device is fully ready after reconnection
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    
    Logger::info("V4L2Capture: Opened device: " + device_path);
    return true;
}

void V4L2Capture::shutdownDevice() {
    if (fd_ >= 0) {
        close(fd_);
        fd_ = -1;
    }
    device_path_.clear();
}

bool V4L2Capture::setupBuffers() {
    // Try DMABUF first for potential zero-copy
    if (trySetupDMABUF()) {
        buffer_type_ = V4L2_MEMORY_DMABUF;
        Logger::info("Using DMABUF for zero-copy operation");
        return true;
    }
    
    // Fallback to MMAP
    buffer_type_ = V4L2_MEMORY_MMAP;
    
    v4l2_requestbuffers reqbuf;
    memset(&reqbuf, 0, sizeof(reqbuf));
    reqbuf.count = kBufferCount;  // ALWAYS 2 buffers (EXTREME minimum)
    reqbuf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    reqbuf.memory = buffer_type_;
    
    if (ioctl(fd_, VIDIOC_REQBUFS, &reqbuf) < 0) {
        setError("Failed to request buffers: " + std::string(strerror(errno)));
        return false;
    }
    
    if (reqbuf.count < 2) {
        setError("Insufficient buffer memory");
        return false;
    }
    
    buffers_.resize(reqbuf.count);
    
    // Map buffers
    for (unsigned int i = 0; i < reqbuf.count; ++i) {
        v4l2_buffer buffer;
        memset(&buffer, 0, sizeof(buffer));
        buffer.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        buffer.memory = V4L2_MEMORY_MMAP;
        buffer.index = i;
        
        if (ioctl(fd_, VIDIOC_QUERYBUF, &buffer) < 0) {
            setError("Failed to query buffer: " + std::string(strerror(errno)));
            cleanupBuffers();
            return false;
        }
        
        buffers_[i].length = buffer.length;
        buffers_[i].start = mmap(NULL, buffer.length,
                                 PROT_READ | PROT_WRITE,
                                 MAP_SHARED, fd_, buffer.m.offset);
        
        if (buffers_[i].start == MAP_FAILED) {
            setError("Failed to map buffer: " + std::string(strerror(errno)));
            cleanupBuffers();
            return false;
        }
        
        // Queue buffer
        if (ioctl(fd_, VIDIOC_QBUF, &buffer) < 0) {
            setError("Failed to queue buffer: " + std::string(strerror(errno)));
            cleanupBuffers();
            return false;
        }
    }
    
    Logger::info("V4L2Capture: Setup " + std::to_string(buffers_.size()) + 
               " buffers (optimized for 8-frame latency)");
    return true;
}

bool V4L2Capture::trySetupDMABUF() {
    // Check if device supports DMABUF
    v4l2_requestbuffers req = {};
    req.count = 1;
    req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    req.memory = V4L2_MEMORY_DMABUF;
    
    if (ioctl(fd_, VIDIOC_REQBUFS, &req) < 0) {
        // DMABUF not supported
        Logger::debug("DMABUF not supported by device");
        return false;
    }
    
    // Reset the request
    req.count = 0;
    ioctl(fd_, VIDIOC_REQBUFS, &req);
    
    dmabuf_supported_ = true;
    Logger::info("Device supports DMABUF (future zero-copy potential)");
    
    // TODO: Implement full DMABUF support with buffer allocation
    // For now, return false to use MMAP
    return false;
}

void V4L2Capture::cleanupBuffers() {
    for (auto& buffer : buffers_) {
        if (buffer.start != nullptr && buffer.start != MAP_FAILED) {
            munmap(buffer.start, buffer.length);
        }
    }
    buffers_.clear();
}

bool V4L2Capture::startStreaming() {
    v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    if (ioctl(fd_, VIDIOC_STREAMON, &type) < 0) {
        setError("Failed to start streaming: " + std::string(strerror(errno)));
        return false;
    }
    
    Logger::info("V4L2Capture: Streaming started");
    return true;
}

void V4L2Capture::stopStreaming() {
    if (fd_ >= 0) {
        v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        if (ioctl(fd_, VIDIOC_STREAMOFF, &type) < 0) {
            Logger::warning("V4L2Capture: Warning - Failed to stop streaming: " + 
                       std::string(strerror(errno)));
        }
    }
}

// Optimized capture thread for stable 60fps
void V4L2Capture::captureThreadExtreme() {
    Logger::info("V4L2 Optimized capture thread started (stable 60fps)");
    
    // Apply real-time settings
    applyExtremeRealtimeSettings();
    
    // Frame timing for stable 60fps
    const auto frame_duration = std::chrono::microseconds(16667); // 60fps = 16.667ms
    auto next_frame_time = std::chrono::steady_clock::now();
    
    // Performance monitoring
    auto last_stats_time = std::chrono::steady_clock::now();
    uint64_t local_frame_count = 0;
    uint64_t total_frame_count = 0;
    uint64_t dropped_frames = 0;
    
    // FPS calculation
    const int fps_window = 60;
    std::chrono::steady_clock::time_point fps_start_time = std::chrono::steady_clock::now();
    uint64_t fps_frame_count = 0;
    
    // Track frame timing
    std::chrono::steady_clock::time_point last_frame_time = std::chrono::steady_clock::now();
    double max_frame_gap_ms = 0.0;
    
    // Use poll for efficient waiting
    struct pollfd pfd;
    pfd.fd = fd_;
    pfd.events = POLLIN;
    
    // Pre-allocate v4l2_buffer
    v4l2_buffer v4l2_buf = {};
    v4l2_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    v4l2_buf.memory = buffer_type_;
    
    Logger::info("V4L2: Thread started, targeting stable 60 FPS");
    
    while (!should_stop_) {
        // Calculate time until next frame
        auto now = std::chrono::steady_clock::now();
        auto time_until_next = next_frame_time - now;
        
        // Use poll with dynamic timeout
        int timeout_ms = 1; // Default 1ms
        if (time_until_next > std::chrono::milliseconds(0)) {
            timeout_ms = std::chrono::duration_cast<std::chrono::milliseconds>(time_until_next).count();
            timeout_ms = std::max(0, std::min(timeout_ms, 16)); // Cap at frame time
        }
        
        // Time poll wait
        auto poll_start = std::chrono::high_resolution_clock::now();
        int ret = poll(&pfd, 1, timeout_ms);
        auto poll_end = std::chrono::high_resolution_clock::now();
        double poll_wait_us = std::chrono::duration<double, std::micro>(poll_end - poll_start).count();
        
        if (ret < 0) {
            if (errno == EINTR) continue;
            setError("Poll error: " + std::string(strerror(errno)));
            break;
        }
        
        if (ret == 0) {
            // Timeout - check if we missed a frame
            if (now > next_frame_time + frame_duration) {
                dropped_frames++;
                next_frame_time = now; // Reset timing
            }
            continue;
        }
        
        // Data available - dequeue buffer with timing
        auto dequeue_start = std::chrono::high_resolution_clock::now();
        if (ioctl(fd_, VIDIOC_DQBUF, &v4l2_buf) < 0) {
            if (errno == EAGAIN) continue;
            setError("Failed to dequeue buffer: " + std::string(strerror(errno)));
            break;
        }
        auto dequeue_end = std::chrono::high_resolution_clock::now();
        double dequeue_us = std::chrono::duration<double, std::micro>(dequeue_end - dequeue_start).count();
        
        // Frame ready - process with timing
        now = std::chrono::steady_clock::now();
        
        // Calculate frame gap
        if (total_frame_count > 0) {
            double frame_gap_ms = std::chrono::duration<double, std::milli>(now - last_frame_time).count();
            if (frame_gap_ms > max_frame_gap_ms) {
                max_frame_gap_ms = frame_gap_ms;
            }
        }
        last_frame_time = now;
        
        // Process frame with zero-copy timing
        auto callback_start = std::chrono::high_resolution_clock::now();
        sendFrameExtreme(buffers_[v4l2_buf.index], v4l2_buf, now);
        auto callback_end = std::chrono::high_resolution_clock::now();
        double callback_us = std::chrono::duration<double, std::micro>(callback_end - callback_start).count();
        
        // Requeue buffer immediately with timing
        auto requeue_start = std::chrono::high_resolution_clock::now();
        if (ioctl(fd_, VIDIOC_QBUF, &v4l2_buf) < 0) {
            setError("Failed to requeue buffer: " + std::string(strerror(errno)));
            break;
        }
        auto requeue_end = std::chrono::high_resolution_clock::now();
        double requeue_us = std::chrono::duration<double, std::micro>(requeue_end - requeue_start).count();
        
        // Update timing statistics
        {
            std::lock_guard<std::mutex> lock(stats_mutex_);
            // Running average
            if (stats_.frames_captured == 0) {
                stats_.avg_poll_wait_us = poll_wait_us;
                stats_.avg_dequeue_us = dequeue_us;
                stats_.avg_callback_us = callback_us;
                stats_.avg_requeue_us = requeue_us;
            } else {
                stats_.avg_poll_wait_us = 0.95 * stats_.avg_poll_wait_us + 0.05 * poll_wait_us;
                stats_.avg_dequeue_us = 0.95 * stats_.avg_dequeue_us + 0.05 * dequeue_us;
                stats_.avg_callback_us = 0.95 * stats_.avg_callback_us + 0.05 * callback_us;
                stats_.avg_requeue_us = 0.95 * stats_.avg_requeue_us + 0.05 * requeue_us;
            }
            // Track maximums
            stats_.max_poll_wait_us = std::max(stats_.max_poll_wait_us, poll_wait_us);
            stats_.max_dequeue_us = std::max(stats_.max_dequeue_us, dequeue_us);
            stats_.max_callback_us = std::max(stats_.max_callback_us, callback_us);
            stats_.max_requeue_us = std::max(stats_.max_requeue_us, requeue_us);
        }
        
        // Update counters
        local_frame_count++;
        total_frame_count++;
        fps_frame_count++;
        
        // Maintain 60fps pacing
        next_frame_time += frame_duration;
        
        // If we're behind, catch up but don't accumulate delay
        now = std::chrono::steady_clock::now();
        if (now > next_frame_time + frame_duration * 2) {
            next_frame_time = now;
        }
        
        // Calculate actual FPS over smaller window
        if (fps_frame_count >= fps_window) {
            auto fps_end_time = std::chrono::steady_clock::now();
            double fps_duration = std::chrono::duration<double>(fps_end_time - fps_start_time).count();
            double actual_fps = fps_frame_count / fps_duration;
            
            // Always log FPS for debugging
            Logger::info("Actual FPS: " + std::to_string(actual_fps) + 
                        " (measured over " + std::to_string(fps_window) + " frames)" +
                        ", max frame gap: " + std::to_string(max_frame_gap_ms) + "ms");
            
            // Reset max frame gap
            max_frame_gap_ms = 0.0;
            
            fps_frame_count = 0;
            fps_start_time = fps_end_time;
        }
        
        // Log statistics periodically
        auto stats_now = std::chrono::steady_clock::now();
        if (stats_now - last_stats_time >= std::chrono::seconds(10)) {
            double elapsed = std::chrono::duration<double>(stats_now - last_stats_time).count();
            double fps = local_frame_count / elapsed;
            
            double total_elapsed = std::chrono::duration<double>(stats_now - fps_start_time).count();
            double overall_fps = total_frame_count / total_elapsed;
            
            std::lock_guard<std::mutex> lock(stats_mutex_);
            Logger::info("V4L2 Performance Stats:");
            Logger::info("  - 10s FPS: " + std::to_string(fps));
            Logger::info("  - Overall FPS: " + std::to_string(overall_fps));
            Logger::info("  - Total frames: " + std::to_string(total_frame_count));
            Logger::info("  - Zero-copy frames: " + std::to_string(stats_.zero_copy_frames));
            Logger::info("  - Internal latency: " + std::to_string(stats_.avg_e2e_latency_ms) + "ms");
            Logger::info("Detailed timing breakdown (microseconds):");
            Logger::info("  - Poll wait: avg=" + std::to_string(stats_.avg_poll_wait_us) + "µs, max=" + std::to_string(stats_.max_poll_wait_us) + "µs");
            Logger::info("  - Dequeue: avg=" + std::to_string(stats_.avg_dequeue_us) + "µs, max=" + std::to_string(stats_.max_dequeue_us) + "µs");
            Logger::info("  - Callback (NDI send): avg=" + std::to_string(stats_.avg_callback_us) + "µs, max=" + std::to_string(stats_.max_callback_us) + "µs");
            Logger::info("  - Requeue: avg=" + std::to_string(stats_.avg_requeue_us) + "µs, max=" + std::to_string(stats_.max_requeue_us) + "µs");
            double total_avg_us = stats_.avg_poll_wait_us + stats_.avg_dequeue_us + stats_.avg_callback_us + stats_.avg_requeue_us;
            Logger::info("  - TOTAL: " + std::to_string(total_avg_us / 1000.0) + "ms (" + std::to_string(total_avg_us) + "µs)");
            
            last_stats_time = stats_now;
            local_frame_count = 0;
        }
    }
    
    // Final stats logged elsewhere
    
    Logger::info("V4L2 capture thread stopped");
    Logger::info("Final stats - Total frames: " + std::to_string(total_frame_count) +
                ", Dropped: " + std::to_string(dropped_frames));
}

void V4L2Capture::sendFrameExtreme(const Buffer& buffer, const v4l2_buffer& v4l2_buf,
                                   std::chrono::steady_clock::time_point capture_time) {
    auto callback_entry = std::chrono::high_resolution_clock::now();
    
    std::lock_guard<std::mutex> lock(callback_mutex_);
    
    if (!frame_callback_) {
        return;
    }
    
    // Get timestamp
    int64_t timestamp_ns = v4l2_buf.timestamp.tv_sec * 1000000000LL + 
                          v4l2_buf.timestamp.tv_usec * 1000LL;
    
    // Update format with actual pixel format for direct pass-through
    VideoFormat format = video_format_;
    if (current_format_.fmt.pix.pixelformat == V4L2_PIX_FMT_UYVY) {
        format.pixel_format = "UYVY";
    } else if (current_format_.fmt.pix.pixelformat == V4L2_PIX_FMT_YUYV) {
        format.pixel_format = "YUYV";  // Will be converted to UYVY by NDI sender
    }
    
    // Direct callback with original YUV data - NO CONVERSION!
    auto actual_send_start = std::chrono::high_resolution_clock::now();
    frame_callback_(buffer.start, v4l2_buf.bytesused, timestamp_ns, format);
    auto actual_send_end = std::chrono::high_resolution_clock::now();
    
    // Calculate detailed timings
    double prep_us = std::chrono::duration<double, std::micro>(actual_send_start - callback_entry).count();
    double send_us = std::chrono::duration<double, std::micro>(actual_send_end - actual_send_start).count();
    
    // Calculate internal processing latency
    auto send_time = std::chrono::steady_clock::now();
    double internal_latency_ms = std::chrono::duration<double, std::milli>(send_time - capture_time).count();
    
    // Update stats
    std::lock_guard<std::mutex> stats_lock(stats_mutex_);
    stats_.frames_captured++;
    stats_.zero_copy_frames++;
    stats_.total_latency_ms += internal_latency_ms;
    
    // Track accurate internal latency
    if (internal_latency_ms > 0 && internal_latency_ms < 10) {  // Sanity check
        if (stats_.e2e_samples == 0) {
            stats_.avg_e2e_latency_ms = internal_latency_ms;
        } else {
            stats_.avg_e2e_latency_ms = 0.9 * stats_.avg_e2e_latency_ms + 0.1 * internal_latency_ms;
        }
        if (internal_latency_ms > stats_.max_e2e_latency_ms) {
            stats_.max_e2e_latency_ms = internal_latency_ms;
        }
        stats_.e2e_samples++;
    }
    
    // Log once for performance tracking
    if (!zero_copy_logged_) {
        Logger::info("EXTREME zero-copy path active: " + format.pixel_format + " -> NDI (NO BGRA CONVERSION)");
        Logger::info("  Callback breakdown: prep=" + std::to_string(prep_us) + "µs, NDI send=" + std::to_string(send_us) + "µs");
        zero_copy_logged_ = true;
    }
    
    // Log detailed timing every 600 frames
    if (stats_.frames_captured % 600 == 0 && stats_.frames_captured > 0) {
        Logger::debug("Frame callback timing: prep=" + std::to_string(prep_us) + "µs, send=" + std::to_string(send_us) + "µs");
    }
}

// Regular single-threaded capture (fallback)
void V4L2Capture::captureThreadSingle() {
    Logger::info("V4L2 capture thread started (FALLBACK MODE)");
    
    // Apply real-time scheduling
    applyRealtimeScheduling();
    
    // Use poll for device readiness
    struct pollfd pfd;
    pfd.fd = fd_;
    pfd.events = POLLIN | POLLPRI;
    
    // Performance monitoring
    auto last_stats_time = std::chrono::steady_clock::now();
    uint64_t local_frame_count = 0;
    
    while (!should_stop_) {
        // Poll with timeout
        int ret = poll(&pfd, 1, 0);  // 0ms timeout
        
        if (ret < 0) {
            if (errno == EINTR) continue;
            setError("Poll error: " + std::string(strerror(errno)));
            break;
        }
        
        if (ret == 0) continue;  // No data yet
        
        // Dequeue buffer
        v4l2_buffer v4l2_buf = {};
        v4l2_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        v4l2_buf.memory = buffer_type_;
        
        if (ioctl(fd_, VIDIOC_DQBUF, &v4l2_buf) < 0) {
            if (errno == EAGAIN) continue;
            setError("Failed to dequeue buffer: " + std::string(strerror(errno)));
            break;
        }
        
        // Direct send (zero-copy)
        sendFrameDirect(buffers_[v4l2_buf.index], v4l2_buf);
        
        // Requeue immediately
        if (ioctl(fd_, VIDIOC_QBUF, &v4l2_buf) < 0) {
            setError("Failed to requeue buffer: " + std::string(strerror(errno)));
            break;
        }
        
        local_frame_count++;
        
        // Log statistics periodically
        auto now = std::chrono::steady_clock::now();
        if (now - last_stats_time >= std::chrono::seconds(10)) {
            std::lock_guard<std::mutex> lock(stats_mutex_);
            Logger::debug("V4L2: FPS: " + std::to_string(local_frame_count / 10) +
                        ", Zero-copy frames: " + std::to_string(stats_.zero_copy_frames) +
                        ", E2E latency: " + std::to_string(stats_.avg_e2e_latency_ms) + "ms");
            
            last_stats_time = now;
            local_frame_count = 0;
        }
    }
    
    Logger::info("V4L2 capture thread stopped");
}

void V4L2Capture::sendFrameDirect(const Buffer& buffer, const v4l2_buffer& v4l2_buf) {
    auto capture_time = std::chrono::steady_clock::now();
    sendFrameExtreme(buffer, v4l2_buf, capture_time);
}

void V4L2Capture::applyRealtimeScheduling() {
    struct sched_param param;
    param.sched_priority = kRealtimePriority;
    
    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &param) != 0) {
        Logger::warning("Could not set real-time priority (need CAP_SYS_NICE)");
        Logger::warning("Run with: sudo setcap cap_sys_nice+ep ndi-bridge");
    } else {
        Logger::info("Real-time SCHED_FIFO priority " + std::to_string(kRealtimePriority) + " active");
    }
    
    // Also try to lock memory
    if (mlockall(MCL_CURRENT | MCL_FUTURE) != 0) {
        Logger::warning("Could not lock memory");
    } else {
        Logger::info("Memory locked (no page faults)");
    }
}

void V4L2Capture::applyExtremeRealtimeSettings() {
    // Set CPU affinity
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(kCpuAffinity, &cpuset);
    
    if (pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset) != 0) {
        Logger::warning("Could not set CPU affinity to core " + std::to_string(kCpuAffinity));
    } else {
        Logger::info("CPU affinity set to core " + std::to_string(kCpuAffinity));
    }
    
    // Set maximum real-time priority
    struct sched_param param;
    param.sched_priority = kRealtimePriority;
    
    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &param) != 0) {
        Logger::warning("Could not set real-time priority " + std::to_string(kRealtimePriority) + 
                       " (need CAP_SYS_NICE)");
        Logger::warning("Run with: sudo setcap 'cap_sys_nice,cap_ipc_lock+ep' ndi-bridge");
    } else {
        Logger::info("EXTREME real-time SCHED_FIFO priority " + std::to_string(kRealtimePriority) + " active");
    }
    
    // Lock memory with MCL_ONFAULT for better performance
    if (mlockall(MCL_CURRENT | MCL_FUTURE | MCL_ONFAULT) != 0) {
        Logger::warning("Could not lock memory (need CAP_IPC_LOCK)");
        Logger::warning("Run with: sudo setcap 'cap_sys_nice,cap_ipc_lock+ep' ndi-bridge");
    } else {
        Logger::info("Memory locked with MCL_ONFAULT (EXTREME mode)");
    }
}

bool V4L2Capture::setCaptureFormat(int width, int height, uint32_t pixelformat) {
    memset(&current_format_, 0, sizeof(current_format_));
    current_format_.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    current_format_.fmt.pix.width = width;
    current_format_.fmt.pix.height = height;
    current_format_.fmt.pix.pixelformat = pixelformat;
    current_format_.fmt.pix.field = V4L2_FIELD_ANY;
    
    if (ioctl(fd_, VIDIOC_S_FMT, &current_format_) < 0) {
        return false;
    }
    
    // Driver may have adjusted the format
    video_format_ = convertFormat(current_format_);
    
    // Try to set highest frame rate for lowest latency
    v4l2_streamparm parm;
    memset(&parm, 0, sizeof(parm));
    parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    
    if (ioctl(fd_, VIDIOC_G_PARM, &parm) == 0) {
        if (parm.parm.capture.capability & V4L2_CAP_TIMEPERFRAME) {
            // Try 60fps first
            parm.parm.capture.timeperframe.numerator = 1;
            parm.parm.capture.timeperframe.denominator = 60;
            
            if (ioctl(fd_, VIDIOC_S_PARM, &parm) < 0) {
                Logger::warning("Failed to set 60fps, trying 30fps");
                // Try 30fps if 60fps fails
                parm.parm.capture.timeperframe.denominator = 30;
                if (ioctl(fd_, VIDIOC_S_PARM, &parm) < 0) {
                    Logger::warning("Failed to set frame rate");
                }
            }
            
            // Read back what we actually got
            if (ioctl(fd_, VIDIOC_G_PARM, &parm) == 0) {
                Logger::info("V4L2: Actual frame rate set to " + 
                           std::to_string(parm.parm.capture.timeperframe.denominator) + "/" +
                           std::to_string(parm.parm.capture.timeperframe.numerator) + " fps");
            }
        } else {
            Logger::warning("Device does not support frame rate setting");
        }
    }
    
    Logger::info("V4L2Capture: Set format to " + std::to_string(video_format_.width) + 
               "x" + std::to_string(video_format_.height) + " " + 
               pixelFormatToString(pixelformat) +
               " @ " + std::to_string(video_format_.fps_numerator) + "/" + 
               std::to_string(video_format_.fps_denominator) + " fps");
    
    return true;
}

bool V4L2Capture::findBestFormat() {
    std::vector<SupportedFormat> formats;
    enumerateFormats(formats);
    
    if (formats.empty()) {
        setError("No supported formats found");
        return false;
    }
    
    // Log all available formats
    Logger::info("Available formats:");
    for (const auto& fmt : formats) {
        Logger::info("  " + pixelFormatToString(fmt.pixelformat) +
                   " " + std::to_string(fmt.width) + "x" + std::to_string(fmt.height) +
                   " @" + std::to_string(fmt.fps) + "fps");
    }
    
    // Try formats in NDI-optimized priority order
    for (uint32_t priority_format : kFormatPriority) {
        for (const auto& fmt : formats) {
            if (fmt.pixelformat == priority_format) {
                // Found a preferred format
                if (setCaptureFormat(fmt.width, fmt.height, fmt.pixelformat)) {
                    Logger::info("Selected OPTIMAL format: " + pixelFormatToString(fmt.pixelformat) +
                               " " + std::to_string(fmt.width) + "x" + std::to_string(fmt.height) +
                               " @" + std::to_string(fmt.fps) + "fps");
                    
                    // Log zero-copy capability
                    if (fmt.pixelformat == V4L2_PIX_FMT_UYVY || 
                        fmt.pixelformat == V4L2_PIX_FMT_YUYV) {
                        Logger::info("Zero-copy mode enabled for " + 
                                   pixelFormatToString(fmt.pixelformat) + 
                                   " (direct to NDI without conversion)");
                    }
                    
                    return true;
                }
            }
        }
    }
    
    // Fallback to first available format
    const auto& fmt = formats[0];
    if (setCaptureFormat(fmt.width, fmt.height, fmt.pixelformat)) {
        Logger::warning("Using non-optimal format: " + 
                       pixelFormatToString(fmt.pixelformat) + 
                       " (will require conversion)");
        return true;
    }
    
    setError("Failed to set any capture format");
    return false;
}

void V4L2Capture::enumerateFormats(std::vector<SupportedFormat>& formats) {
    v4l2_fmtdesc fmtdesc;
    memset(&fmtdesc, 0, sizeof(fmtdesc));
    fmtdesc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    
    while (ioctl(fd_, VIDIOC_ENUM_FMT, &fmtdesc) == 0) {
        // Enumerate frame sizes for this format
        v4l2_frmsizeenum frmsize;
        memset(&frmsize, 0, sizeof(frmsize));
        frmsize.pixel_format = fmtdesc.pixelformat;
        frmsize.index = 0;
        
        while (ioctl(fd_, VIDIOC_ENUM_FRAMESIZES, &frmsize) == 0) {
            if (frmsize.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
                // Enumerate frame rates for this size
                v4l2_frmivalenum frmival;
                memset(&frmival, 0, sizeof(frmival));
                frmival.pixel_format = fmtdesc.pixelformat;
                frmival.width = frmsize.discrete.width;
                frmival.height = frmsize.discrete.height;
                frmival.index = 0;
                
                uint32_t max_fps = 0;
                
                while (ioctl(fd_, VIDIOC_ENUM_FRAMEINTERVALS, &frmival) == 0) {
                    if (frmival.type == V4L2_FRMIVAL_TYPE_DISCRETE) {
                        uint32_t fps = frmival.discrete.denominator / frmival.discrete.numerator;
                        if (fps > max_fps) {
                            max_fps = fps;
                        }
                    }
                    frmival.index++;
                }
                
                if (max_fps == 0) {
                    max_fps = 30; // Default if enumeration fails
                }
                
                SupportedFormat fmt;
                fmt.pixelformat = fmtdesc.pixelformat;
                fmt.width = frmsize.discrete.width;
                fmt.height = frmsize.discrete.height;
                fmt.fps = max_fps;
                formats.push_back(fmt);
            }
            frmsize.index++;
        }
        
        fmtdesc.index++;
    }
}

bool V4L2Capture::queryCapabilities() {
    if (ioctl(fd_, VIDIOC_QUERYCAP, &device_caps_) < 0) {
        setError("Failed to query capabilities: " + std::string(strerror(errno)));
        return false;
    }
    
    if (!(device_caps_.capabilities & V4L2_CAP_VIDEO_CAPTURE)) {
        setError("Device does not support video capture");
        return false;
    }
    
    if (!(device_caps_.capabilities & V4L2_CAP_STREAMING)) {
        setError("Device does not support streaming");
        return false;
    }
    
    Logger::info("V4L2Capture: Device capabilities verified");
    return true;
}

ICaptureDevice::VideoFormat V4L2Capture::convertFormat(const v4l2_format& fmt) const {
    VideoFormat format;
    format.width = fmt.fmt.pix.width;
    format.height = fmt.fmt.pix.height;
    format.stride = fmt.fmt.pix.bytesperline;
    
    // Convert pixel format
    char fourcc[5] = {0};
    fourcc[0] = (fmt.fmt.pix.pixelformat >> 0) & 0xFF;
    fourcc[1] = (fmt.fmt.pix.pixelformat >> 8) & 0xFF;
    fourcc[2] = (fmt.fmt.pix.pixelformat >> 16) & 0xFF;
    fourcc[3] = (fmt.fmt.pix.pixelformat >> 24) & 0xFF;
    format.pixel_format = std::string(fourcc);
    
    // Get frame rate
    v4l2_streamparm parm;
    memset(&parm, 0, sizeof(parm));
    parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    
    if (ioctl(fd_, VIDIOC_G_PARM, &parm) == 0) {
        if (parm.parm.capture.timeperframe.denominator > 0 && 
            parm.parm.capture.timeperframe.numerator > 0) {
            format.fps_numerator = parm.parm.capture.timeperframe.denominator;
            format.fps_denominator = parm.parm.capture.timeperframe.numerator;
        } else {
            format.fps_numerator = 30;
            format.fps_denominator = 1;
        }
    } else {
        // Default to 30 fps
        format.fps_numerator = 30;
        format.fps_denominator = 1;
    }
    
    return format;
}

std::string V4L2Capture::pixelFormatToString(uint32_t format) const {
    switch (format) {
        case V4L2_PIX_FMT_UYVY: return "UYVY";
        case V4L2_PIX_FMT_YUYV: return "YUYV";
        case V4L2_PIX_FMT_NV12: return "NV12";
        case V4L2_PIX_FMT_YUV420: return "YUV420";
        case V4L2_PIX_FMT_MJPEG: return "MJPEG";
        case V4L2_PIX_FMT_H264: return "H264";
        case V4L2_PIX_FMT_RGB24: return "RGB24";
        case V4L2_PIX_FMT_BGR24: return "BGR24";
        case V4L2_PIX_FMT_RGB32: return "RGB32";
        case V4L2_PIX_FMT_BGR32: return "BGR32";
        default: {
            char fourcc[5] = {0};
            fourcc[0] = format & 0xFF;
            fourcc[1] = (format >> 8) & 0xFF;
            fourcc[2] = (format >> 16) & 0xFF;
            fourcc[3] = (format >> 24) & 0xFF;
            return std::string(fourcc);
        }
    }
}

void V4L2Capture::setError(const std::string& error) {
    {
        std::lock_guard<std::mutex> lock(error_mutex_);
        last_error_ = error;
        has_error_ = true;
    }
    
    Logger::error("V4L2Capture Error: " + error);
    
    ErrorCallback callback;
    {
        std::lock_guard<std::mutex> lock(callback_mutex_);
        callback = error_callback_;
    }
    
    if (callback) {
        callback(error);
    }
}

V4L2Capture::CaptureStats V4L2Capture::getStats() const {
    std::lock_guard<std::mutex> lock(stats_mutex_);
    return stats_;
}

// REMOVED ALL CONFIGURATION METHODS - NO setLowLatencyMode, setMultiThreadingEnabled, etc.
// Everything is hardcoded for MAXIMUM PERFORMANCE

// Old multi-threaded functions REMOVED - only single-threaded ultra-low latency remains

// processFrame() REMOVED - always use sendFrameDirect() for zero-copy

} // namespace v4l2
} // namespace ndi_bridge
