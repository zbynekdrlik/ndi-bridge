// v4l2_capture.cpp
#include "v4l2_capture.h"
#include "../../common/logger.h"
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

namespace ndi_bridge {
namespace v4l2 {

V4L2Capture::V4L2Capture() 
    : fd_(-1)
    , capturing_(false)
    , should_stop_(false)
    , has_error_(false) {
    Logger::info("V4L2Capture: Created");
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
    
    // Start capture thread
    should_stop_ = false;
    capturing_ = true;
    capture_thread_ = std::make_unique<std::thread>(&V4L2Capture::captureThread, this);
    
    Logger::info("V4L2Capture: Capture started successfully");
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

bool V4L2Capture::initializeDevice(const std::string& device_path) {
    device_path_ = device_path;
    
    // Open device
    fd_ = open(device_path.c_str(), O_RDWR | O_NONBLOCK);
    if (fd_ < 0) {
        setError("Failed to open device " + device_path + ": " + strerror(errno));
        return false;
    }
    
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
    v4l2_requestbuffers reqbuf;
    memset(&reqbuf, 0, sizeof(reqbuf));
    reqbuf.count = kBufferCount;
    reqbuf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    reqbuf.memory = V4L2_MEMORY_MMAP;
    
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
    
    Logger::info("V4L2Capture: Setup " + std::to_string(buffers_.size()) + " buffers");
    return true;
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

void V4L2Capture::captureThread() {
    Logger::info("V4L2Capture: Capture thread started");
    
    // Use poll instead of select for better performance
    struct pollfd pfd;
    pfd.fd = fd_;
    pfd.events = POLLIN | POLLPRI;
    
    // Pre-allocate conversion buffer for better performance
    std::vector<uint8_t> bgra_buffer;
    bool needs_conversion = (current_format_.fmt.pix.pixelformat != V4L2_PIX_FMT_YUYV) && 
                           V4L2FormatConverter::isFormatSupported(current_format_.fmt.pix.pixelformat);
    
    if (needs_conversion) {
        size_t bgra_size = V4L2FormatConverter::calculateBGRASize(video_format_.width, video_format_.height);
        bgra_buffer.reserve(bgra_size);
    }
    
    // Performance monitoring
    auto last_stats_time = std::chrono::steady_clock::now();
    uint64_t local_frame_count = 0;
    
    while (!should_stop_) {
        // Use low timeout for minimal latency (5ms)
        int ret = poll(&pfd, 1, 5);
        
        if (ret < 0) {
            if (errno == EINTR) {
                continue;
            }
            // Check if device was disconnected
            if (errno == ENODEV) {
                setError("Device disconnected");
                break;
            }
            setError("Poll error: " + std::string(strerror(errno)));
            break;
        }
        
        if (ret == 0) {
            // Timeout - check if device still exists
            if (++timeout_count_ > 200) { // 1 second without frames
                struct v4l2_capability cap;
                if (ioctl(fd_, VIDIOC_QUERYCAP, &cap) < 0) {
                    setError("Device disconnected or not responding");
                    break;
                }
                timeout_count_ = 0;
            }
            continue;
        }
        
        timeout_count_ = 0;
        
        // Check for errors
        if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) {
            setError("Device error detected");
            break;
        }
        
        // Dequeue buffer
        v4l2_buffer v4l2_buf;
        memset(&v4l2_buf, 0, sizeof(v4l2_buf));
        v4l2_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        v4l2_buf.memory = V4L2_MEMORY_MMAP;
        
        auto dequeue_start = std::chrono::high_resolution_clock::now();
        
        if (ioctl(fd_, VIDIOC_DQBUF, &v4l2_buf) < 0) {
            if (errno == EAGAIN) {
                continue;
            }
            setError("Failed to dequeue buffer: " + std::string(strerror(errno)));
            break;
        }
        
        // Process frame
        if (v4l2_buf.index < buffers_.size()) {
            processFrame(buffers_[v4l2_buf.index], v4l2_buf, bgra_buffer);
            
            // Update statistics
            auto now = std::chrono::high_resolution_clock::now();
            auto dequeue_time = std::chrono::duration<double, std::milli>(now - dequeue_start).count();
            
            std::lock_guard<std::mutex> lock(stats_mutex_);
            stats_.frames_captured++;
            stats_.total_latency_ms += dequeue_time;
            
            if (dequeue_time > stats_.max_latency_ms) {
                stats_.max_latency_ms = dequeue_time;
            }
            if (dequeue_time < stats_.min_latency_ms) {
                stats_.min_latency_ms = dequeue_time;
            }
            
            local_frame_count++;
        }
        
        // Requeue buffer
        if (ioctl(fd_, VIDIOC_QBUF, &v4l2_buf) < 0) {
            setError("Failed to requeue buffer: " + std::string(strerror(errno)));
            break;
        }
        
        // Log statistics periodically
        auto now = std::chrono::steady_clock::now();
        if (now - last_stats_time >= std::chrono::seconds(10)) {
            double avg_latency = stats_.frames_captured > 0 ? 
                stats_.total_latency_ms / stats_.frames_captured : 0.0;
            
            Logger::debug("V4L2Capture: Stats - FPS: " + 
                std::to_string(local_frame_count / 10) +
                ", Avg latency: " + std::to_string(avg_latency) + "ms" +
                ", Max: " + std::to_string(stats_.max_latency_ms) + "ms" +
                ", Zero-copy: " + std::to_string(stats_.zero_copy_frames));
            
            last_stats_time = now;
            local_frame_count = 0;
        }
    }
    
    Logger::info("V4L2Capture: Capture thread stopped");
}

void V4L2Capture::processFrame(const Buffer& buffer, const v4l2_buffer& v4l2_buf, 
                               std::vector<uint8_t>& bgra_buffer) {
    FrameCallback callback;
    {
        std::lock_guard<std::mutex> lock(callback_mutex_);
        callback = frame_callback_;
    }
    
    if (!callback) {
        return;
    }
    
    // Use hardware timestamp if available, otherwise use system time
    int64_t timestamp;
    if (v4l2_buf.flags & V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC) {
        // Convert v4l2 timestamp to nanoseconds
        timestamp = v4l2_buf.timestamp.tv_sec * 1000000000LL + v4l2_buf.timestamp.tv_usec * 1000LL;
    } else {
        timestamp = std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
    }
    
    // Check if we can use zero-copy for YUYV format
    bool use_zero_copy = false;
    if (current_format_.fmt.pix.pixelformat == V4L2_PIX_FMT_YUYV) {
        // YUYV can be sent directly to NDI (will be converted to UYVY in NDI sender)
        use_zero_copy = true;
        
        // Log once for tracking
        if (!zero_copy_logged_) {
            Logger::info("V4L2Capture: Using zero-copy path for YUYV format");
            zero_copy_logged_ = true;
        }
    }
    
    if (use_zero_copy) {
        // Direct pass-through for YUYV format
        callback(buffer.start, v4l2_buf.bytesused, timestamp, video_format_);
        
        // No conversion time to track
        std::lock_guard<std::mutex> lock(stats_mutex_);
        stats_.zero_copy_frames++;
    } else if (V4L2FormatConverter::isFormatSupported(current_format_.fmt.pix.pixelformat)) {
        // Convert other supported formats to BGRA
        if (!format_converter_) {
            format_converter_ = std::make_unique<V4L2FormatConverter>();
        }
        
        auto convert_start = std::chrono::high_resolution_clock::now();
        
        if (format_converter_->convertToBGRA(buffer.start, v4l2_buf.bytesused,
                                              video_format_.width, video_format_.height,
                                              current_format_.fmt.pix.pixelformat,
                                              bgra_buffer)) {
            // Update format for BGRA
            VideoFormat bgra_format = video_format_;
            bgra_format.pixel_format = "BGRA";
            bgra_format.stride = video_format_.width * 4;
            
            callback(bgra_buffer.data(), bgra_buffer.size(), timestamp, bgra_format);
            
            // Track conversion time
            auto convert_time = std::chrono::duration<double, std::milli>(
                std::chrono::high_resolution_clock::now() - convert_start).count();
            
            std::lock_guard<std::mutex> lock(stats_mutex_);
            stats_.total_convert_ms += convert_time;
        } else {
            Logger::error("V4L2Capture: Failed to convert frame to BGRA");
            std::lock_guard<std::mutex> lock(stats_mutex_);
            stats_.frames_dropped++;
        }
    } else {
        // Pass through unsupported format
        callback(buffer.start, v4l2_buf.bytesused, timestamp, video_format_);
    }
}

bool V4L2Capture::setCaptureFormat(int width, int height, uint32_t pixelformat) {
    memset(&current_format_, 0, sizeof(current_format_));
    current_format_.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    current_format_.fmt.pix.width = width;
    current_format_.fmt.pix.height = height;
    current_format_.fmt.pix.pixelformat = pixelformat;
    current_format_.fmt.pix.field = V4L2_FIELD_ANY;  // Let driver choose
    
    if (ioctl(fd_, VIDIOC_S_FMT, &current_format_) < 0) {
        return false;
    }
    
    // Driver may have adjusted the format
    video_format_ = convertFormat(current_format_);
    
    // Try to set frame rate for low latency
    v4l2_streamparm parm;
    memset(&parm, 0, sizeof(parm));
    parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    
    if (ioctl(fd_, VIDIOC_G_PARM, &parm) == 0) {
        if (parm.parm.capture.capability & V4L2_CAP_TIMEPERFRAME) {
            // Try to set 60fps for lowest latency
            parm.parm.capture.timeperframe.numerator = 1;
            parm.parm.capture.timeperframe.denominator = 60;
            
            if (ioctl(fd_, VIDIOC_S_PARM, &parm) < 0) {
                // Try 30fps if 60fps fails
                parm.parm.capture.timeperframe.denominator = 30;
                ioctl(fd_, VIDIOC_S_PARM, &parm);
            }
        }
    }
    
    Logger::info("V4L2Capture: Set format to " + std::to_string(video_format_.width) + 
               "x" + std::to_string(video_format_.height) + " " + video_format_.pixel_format +
               " @ " + std::to_string(video_format_.fps_numerator) + "/" + 
               std::to_string(video_format_.fps_denominator) + " fps");
    
    return true;
}

bool V4L2Capture::findBestFormat() {
    // First enumerate all supported formats
    std::vector<SupportedFormat> supported_formats;
    enumerateFormats(supported_formats);
    
    if (supported_formats.empty()) {
        setError("No supported formats found");
        return false;
    }
    
    // Log available formats
    Logger::info("V4L2Capture: Device supports " + std::to_string(supported_formats.size()) + " formats:");
    for (const auto& fmt : supported_formats) {
        Logger::debug("  " + V4L2FormatConverter::getFormatName(fmt.pixelformat) +
                     " " + std::to_string(fmt.width) + "x" + std::to_string(fmt.height) +
                     " @ " + std::to_string(fmt.fps) + " fps");
    }
    
    // Prefer formats in this order: YUYV > UYVY > NV12 > RGB24 > BGR24 > MJPEG
    const uint32_t preferred_formats[] = {
        V4L2_PIX_FMT_YUYV,
        V4L2_PIX_FMT_UYVY,
        V4L2_PIX_FMT_NV12,
        V4L2_PIX_FMT_RGB24,
        V4L2_PIX_FMT_BGR24,
        V4L2_PIX_FMT_MJPEG  // Last resort due to decompression overhead
    };
    
    // Try to find best format
    for (auto pix_fmt : preferred_formats) {
        // Try 1080p first, then 720p, then 480p
        const uint32_t resolutions[][2] = {{1920, 1080}, {1280, 720}, {640, 480}};
        
        for (auto res : resolutions) {
            // Find matching format with highest FPS
            auto best = std::find_if(supported_formats.begin(), supported_formats.end(),
                [&](const SupportedFormat& f) {
                    return f.pixelformat == pix_fmt && 
                           f.width == res[0] && f.height == res[1];
                });
            
            if (best != supported_formats.end()) {
                if (setCaptureFormat(best->width, best->height, best->pixelformat)) {
                    return true;
                }
            }
        }
    }
    
    // Fallback: use first available format
    const auto& fallback = supported_formats[0];
    return setCaptureFormat(fallback.width, fallback.height, fallback.pixelformat);
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

} // namespace v4l2
} // namespace ndi_bridge
