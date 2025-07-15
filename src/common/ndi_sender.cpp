#include "ndi_sender.h"
#include "logger.h"
#include "version.h"
#include <Processing.NDI.Lib.h>
#include <chrono>
#include <cstring>

namespace ndi_bridge {

// Static member definitions
std::mutex NdiSender::lib_mutex_;
int NdiSender::lib_ref_count_ = 0;

// Constants
constexpr int CONNECTION_CHECK_TIMEOUT_MS = 5000;

NdiSender::NdiSender(const std::string& sender_name, ErrorCallback error_callback)
    : sender_name_(sender_name)
    , error_callback_(std::move(error_callback)) {
    Logger::initialize("NdiSender");
    Logger::logVersion(NDI_BRIDGE_VERSION);
}

NdiSender::~NdiSender() {
    shutdown();
}

NdiSender::NdiSender(NdiSender&& other) noexcept
    : sender_name_(std::move(other.sender_name_))
    , error_callback_(std::move(other.error_callback_))
    , initialized_(other.initialized_.load())
    , frames_sent_(other.frames_sent_.load())
    , ndi_send_instance_(other.ndi_send_instance_) {
    other.ndi_send_instance_ = nullptr;
    other.initialized_ = false;
}

NdiSender& NdiSender::operator=(NdiSender&& other) noexcept {
    if (this != &other) {
        shutdown();
        
        sender_name_ = std::move(other.sender_name_);
        error_callback_ = std::move(other.error_callback_);
        initialized_ = other.initialized_.load();
        frames_sent_ = other.frames_sent_.load();
        ndi_send_instance_ = other.ndi_send_instance_;
        
        other.ndi_send_instance_ = nullptr;
        other.initialized_ = false;
    }
    return *this;
}

bool NdiSender::initialize() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (initialized_) {
        return true;
    }

    Logger::info("Initializing NDI sender: " + sender_name_);

    // Initialize NDI library
    if (!loadNdiLibrary()) {
        reportError("Failed to load NDI library");
        return false;
    }

    // Create sender
    if (!createSender()) {
        reportError("Failed to create NDI sender");
        cleanup();
        return false;
    }

    initialized_ = true;
    Logger::info("NDI sender initialized successfully");
    return true;
}

void NdiSender::shutdown() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (!initialized_) {
        return;
    }

    Logger::info("Shutting down NDI sender");
    cleanup();
    initialized_ = false;
}

bool NdiSender::sendFrame(const FrameInfo& frame) {
    if (!initialized_) {
        reportError("NDI sender not initialized");
        return false;
    }

    if (!frame.data || frame.width == 0 || frame.height == 0) {
        reportError("Invalid frame data");
        return false;
    }

    // Create NDI video frame
    NDIlib_video_frame_v2_t ndi_frame;
    ndi_frame.xres = frame.width;
    ndi_frame.yres = frame.height;
    ndi_frame.line_stride_in_bytes = frame.stride;
    ndi_frame.p_data = const_cast<uint8_t*>(static_cast<const uint8_t*>(frame.data));
    ndi_frame.timecode = frame.timestamp_ns / 100;  // Convert to 100ns units
    
    // Set format based on FourCC
    switch (frame.fourcc) {
        case NDIlib_FourCC_type_UYVY:
            ndi_frame.FourCC = NDIlib_FourCC_type_UYVY;
            break;
        case NDIlib_FourCC_type_BGRA:
            ndi_frame.FourCC = NDIlib_FourCC_type_BGRA;
            break;
        case NDIlib_FourCC_type_BGRX:
            ndi_frame.FourCC = NDIlib_FourCC_type_BGRX;
            break;
        case NDIlib_FourCC_type_RGBA:
            ndi_frame.FourCC = NDIlib_FourCC_type_RGBA;
            break;
        case NDIlib_FourCC_type_RGBX:
            ndi_frame.FourCC = NDIlib_FourCC_type_RGBX;
            break;
        default:
            reportError("Unsupported pixel format");
            return false;
    }

    // Set frame metadata
    ndi_frame.frame_rate_N = frame.fps_numerator;    // Use actual frame rate from capture
    ndi_frame.frame_rate_D = frame.fps_denominator;  // Use actual frame rate from capture
    ndi_frame.picture_aspect_ratio = static_cast<float>(frame.width) / frame.height;
    ndi_frame.frame_format_type = NDIlib_frame_format_type_progressive;
    ndi_frame.p_metadata = nullptr;

    // Send the frame
    NDIlib_send_send_video_v2(ndi_send_instance_, &ndi_frame);
    
    frames_sent_++;
    return true;
}

bool NdiSender::isReady() const {
    return initialized_ && ndi_send_instance_ != nullptr;
}

int NdiSender::getConnectionCount() const {
    if (!initialized_ || !ndi_send_instance_) {
        return 0;
    }

    // Get connection info
    int no_connections = NDIlib_send_get_no_connections(ndi_send_instance_, CONNECTION_CHECK_TIMEOUT_MS);
    return no_connections;
}

bool NdiSender::isNdiAvailable() {
    // Try to find NDI runtime
    const NDIlib_find_create_t find_create = {true, nullptr, nullptr};
    NDIlib_find_instance_t finder = NDIlib_find_create_v2(&find_create);
    
    if (!finder) {
        return false;
    }
    
    NDIlib_find_destroy(finder);
    return true;
}

std::string NdiSender::getNdiVersion() {
    const char* version = NDIlib_version();
    return version ? version : "Unknown";
}

bool NdiSender::loadNdiLibrary() {
    std::lock_guard<std::mutex> lock(lib_mutex_);
    
    // Already loaded
    if (lib_ref_count_ > 0) {
        lib_ref_count_++;
        return true;
    }

    // Initialize NDI
    if (!NDIlib_initialize()) {
        Logger::error("Failed to initialize NDI library");
        return false;
    }

    Logger::info("NDI library version: " + getNdiVersion());
    
    lib_ref_count_++;
    return true;
}

bool NdiSender::createSender() {
    // Create NDI sender description
    NDIlib_send_create_t send_create;
    send_create.p_ndi_name = sender_name_.c_str();
    send_create.clock_video = true;
    send_create.clock_audio = false;

    // Create the sender
    ndi_send_instance_ = NDIlib_send_create(&send_create);
    if (!ndi_send_instance_) {
        Logger::error("Failed to create NDI sender instance");
        return false;
    }

    Logger::info("Created NDI sender: " + sender_name_);
    return true;
}

void NdiSender::cleanup() {
    // Destroy sender instance
    if (ndi_send_instance_) {
        NDIlib_send_destroy(ndi_send_instance_);
        ndi_send_instance_ = nullptr;
        Logger::info("Destroyed NDI sender instance");
    }

    // Decrement library reference count
    {
        std::lock_guard<std::mutex> lock(lib_mutex_);
        if (--lib_ref_count_ == 0) {
            NDIlib_destroy();
            Logger::info("NDI library unloaded");
        }
    }
}

void NdiSender::reportError(const std::string& error) {
    Logger::error("Error: " + error);
    
    if (error_callback_) {
        error_callback_(error);
    }
}

} // namespace ndi_bridge
