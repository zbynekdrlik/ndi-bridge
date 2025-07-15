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

namespace ndi_bridge {
namespace v4l2 {

V4L2Capture::V4L2Capture() 
    : fd_(-1)
    , capturing_(false)
    , should_stop_(false)
    , has_error_(false) {
    Logger::log("V4L2Capture: Created");
    memset(&current_format_, 0, sizeof(current_format_));
    memset(&device_caps_, 0, sizeof(device_caps_));
}

V4L2Capture::~V4L2Capture() {
    stopCapture();
    Logger::log("V4L2Capture: Destroyed");
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
    
    Logger::log("V4L2Capture: Found " + std::to_string(devices.size()) + " capture devices");
    return devices;
}

bool V4L2Capture::startCapture(const std::string& device_name) {
    if (isCapturing()) {
        Logger::log("V4L2Capture: Already capturing");
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
    
    Logger::log("V4L2Capture: Starting capture with device: " + device_path);
    
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
    
    // Start capture thread
    should_stop_ = false;
    capturing_ = true;
    capture_thread_ = std::make_unique<std::thread>(&V4L2Capture::captureThread, this);
    
    Logger::log("V4L2Capture: Capture started successfully");
    return true;
}

void V4L2Capture::stopCapture() {
    if (!isCapturing()) {
        return;
    }
    
    Logger::log("V4L2Capture: Stopping capture");
    
    // Signal thread to stop
    should_stop_ = true;
    
    // Wait for thread to finish
    if (capture_thread_ && capture_thread_->joinable()) {
        capture_thread_->join();
    }
    capture_thread_.reset();
    
    capturing_ = false;
    
    // Stop streaming
    stopStreaming();
    
    // Cleanup
    cleanupBuffers();
    shutdownDevice();
    
    Logger::log("V4L2Capture: Capture stopped");
}

bool V4L2Capture::isCapturing() const {
    return capturing_;
}

void V4L2Capture::setFrameCallback(FrameCallback callback) {
    frame_callback_ = callback;
}

void V4L2Capture::setErrorCallback(ErrorCallback callback) {
    error_callback_ = callback;
}

bool V4L2Capture::hasError() const {
    return has_error_;
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
    
    Logger::log("V4L2Capture: Opened device: " + device_path);
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
    
    Logger::log("V4L2Capture: Setup " + std::to_string(buffers_.size()) + " buffers");
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
    
    Logger::log("V4L2Capture: Streaming started");
    return true;
}

void V4L2Capture::stopStreaming() {
    if (fd_ >= 0) {
        v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        if (ioctl(fd_, VIDIOC_STREAMOFF, &type) < 0) {
            Logger::log("V4L2Capture: Warning - Failed to stop streaming: " + 
                       std::string(strerror(errno)));
        }
    }
}

void V4L2Capture::captureThread() {
    Logger::log("V4L2Capture: Capture thread started");
    
    fd_set fds;
    struct timeval tv;
    
    while (!should_stop_) {
        FD_ZERO(&fds);
        FD_SET(fd_, &fds);
        
        // Timeout
        tv.tv_sec = 0;
        tv.tv_usec = 100000; // 100ms
        
        int ret = select(fd_ + 1, &fds, NULL, NULL, &tv);
        
        if (ret < 0) {
            if (errno == EINTR) {
                continue;
            }
            setError("Select error: " + std::string(strerror(errno)));
            break;
        }
        
        if (ret == 0) {
            // Timeout - check if we should stop
            continue;
        }
        
        // Dequeue buffer
        v4l2_buffer v4l2_buf;
        memset(&v4l2_buf, 0, sizeof(v4l2_buf));
        v4l2_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        v4l2_buf.memory = V4L2_MEMORY_MMAP;
        
        if (ioctl(fd_, VIDIOC_DQBUF, &v4l2_buf) < 0) {
            if (errno == EAGAIN) {
                continue;
            }
            setError("Failed to dequeue buffer: " + std::string(strerror(errno)));
            break;
        }
        
        // Process frame
        if (v4l2_buf.index < buffers_.size()) {
            processFrame(buffers_[v4l2_buf.index], v4l2_buf);
        }
        
        // Requeue buffer
        if (ioctl(fd_, VIDIOC_QBUF, &v4l2_buf) < 0) {
            setError("Failed to requeue buffer: " + std::string(strerror(errno)));
            break;
        }
    }
    
    Logger::log("V4L2Capture: Capture thread stopped");
}

void V4L2Capture::processFrame(const Buffer& buffer, const v4l2_buffer& v4l2_buf) {
    if (!frame_callback_) {
        return;
    }
    
    // Get timestamp
    auto timestamp = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    
    // Convert format if needed
    if (V4L2FormatConverter::isFormatSupported(current_format_.fmt.pix.pixelformat)) {
        std::vector<uint8_t> bgra_buffer;
        
        if (!format_converter_) {
            format_converter_ = std::make_unique<V4L2FormatConverter>();
        }
        
        if (format_converter_->convertToBGRA(buffer.start, v4l2_buf.bytesused,
                                              video_format_.width, video_format_.height,
                                              current_format_.fmt.pix.pixelformat,
                                              bgra_buffer)) {
            // Update format for BGRA
            VideoFormat bgra_format = video_format_;
            bgra_format.pixel_format = "BGRA";
            bgra_format.stride = video_format_.width * 4;
            
            frame_callback_(bgra_buffer.data(), bgra_buffer.size(), timestamp, bgra_format);
        } else {
            Logger::log("V4L2Capture: Failed to convert frame to BGRA");
        }
    } else {
        // Pass through unsupported format
        frame_callback_(buffer.start, v4l2_buf.bytesused, timestamp, video_format_);
    }
}

bool V4L2Capture::setCaptureFormat(int width, int height, uint32_t pixelformat) {
    memset(&current_format_, 0, sizeof(current_format_));
    current_format_.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    current_format_.fmt.pix.width = width;
    current_format_.fmt.pix.height = height;
    current_format_.fmt.pix.pixelformat = pixelformat;
    current_format_.fmt.pix.field = V4L2_FIELD_INTERLACED;
    
    if (ioctl(fd_, VIDIOC_S_FMT, &current_format_) < 0) {
        setError("Failed to set format: " + std::string(strerror(errno)));
        return false;
    }
    
    // Driver may have adjusted the format
    video_format_ = convertFormat(current_format_);
    
    Logger::log("V4L2Capture: Set format to " + std::to_string(video_format_.width) + 
               "x" + std::to_string(video_format_.height) + " " + video_format_.pixel_format);
    
    return true;
}

bool V4L2Capture::findBestFormat() {
    // Try common formats in order of preference
    const struct {
        int width;
        int height;
        uint32_t pixelformat;
    } formats[] = {
        {1920, 1080, V4L2_PIX_FMT_YUYV},
        {1920, 1080, V4L2_PIX_FMT_MJPEG},
        {1280, 720,  V4L2_PIX_FMT_YUYV},
        {1280, 720,  V4L2_PIX_FMT_MJPEG},
        {640,  480,  V4L2_PIX_FMT_YUYV},
        {640,  480,  V4L2_PIX_FMT_MJPEG}
    };
    
    for (const auto& fmt : formats) {
        if (setCaptureFormat(fmt.width, fmt.height, fmt.pixelformat)) {
            return true;
        }
    }
    
    // Try to get any supported format
    v4l2_fmtdesc fmtdesc;
    memset(&fmtdesc, 0, sizeof(fmtdesc));
    fmtdesc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    
    while (ioctl(fd_, VIDIOC_ENUM_FMT, &fmtdesc) == 0) {
        // Try to set this format
        memset(&current_format_, 0, sizeof(current_format_));
        current_format_.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
        
        if (ioctl(fd_, VIDIOC_G_FMT, &current_format_) == 0) {
            video_format_ = convertFormat(current_format_);
            Logger::log("V4L2Capture: Using default format");
            return true;
        }
        
        fmtdesc.index++;
    }
    
    setError("No suitable capture format found");
    return false;
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
    
    Logger::log("V4L2Capture: Device capabilities verified");
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
    
    // Get frame rate (many devices don't support this properly)
    v4l2_streamparm parm;
    memset(&parm, 0, sizeof(parm));
    parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    
    if (ioctl(fd_, VIDIOC_G_PARM, &parm) == 0) {
        if (parm.parm.capture.timeperframe.denominator > 0) {
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
    
    Logger::log("V4L2Capture Error: " + error);
    
    if (error_callback_) {
        error_callback_(error);
    }
}

} // namespace v4l2
} // namespace ndi_bridge
