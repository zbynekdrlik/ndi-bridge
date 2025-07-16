#include "ndi_sender.h"
#include "logger.h"
#include "version.h"
#include <Processing.NDI.Lib.h>
#include <chrono>
#include <cstring>
#include <immintrin.h>  // For AVX2

#ifdef _MSC_VER
#include <intrin.h>  // For __cpuid on Windows
#endif

namespace ndi_bridge {

// Static member definitions
std::mutex NdiSender::lib_mutex_;
int NdiSender::lib_ref_count_ = 0;

// Constants
constexpr int CONNECTION_CHECK_TIMEOUT_MS = 5000;

// Custom FourCC for YUYV (not in NDI SDK)
constexpr uint32_t FOURCC_YUYV = 0x56595559;  // 'YUYV'

// CPU feature detection helper
static bool detectAVX2Support() {
#if defined(__GNUC__) || defined(__clang__)
    // GCC/Clang
    return __builtin_cpu_supports("avx2");
#elif defined(_MSC_VER)
    // MSVC
    int cpuInfo[4];
    __cpuid(cpuInfo, 0);
    int nIds = cpuInfo[0];
    
    if (nIds >= 7) {
        __cpuidex(cpuInfo, 7, 0);
        return (cpuInfo[1] & (1 << 5)) != 0;  // AVX2 bit
    }
    return false;
#else
    // Unknown compiler - assume no AVX2
    return false;
#endif
}

NdiSender::NdiSender(const std::string& sender_name, ErrorCallback error_callback)
    : sender_name_(sender_name)
    , error_callback_(std::move(error_callback)) {
}

NdiSender::~NdiSender() {
    shutdown();
}

NdiSender::NdiSender(NdiSender&& other) noexcept
    : sender_name_(std::move(other.sender_name_))
    , error_callback_(std::move(other.error_callback_))
    , initialized_(other.initialized_.load())
    , frames_sent_(other.frames_sent_.load())
    , ndi_send_instance_(other.ndi_send_instance_)
    , yuyv_to_uyvy_buffer_(std::move(other.yuyv_to_uyvy_buffer_)) {
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
        yuyv_to_uyvy_buffer_ = std::move(other.yuyv_to_uyvy_buffer_);
        
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

    // Check CPU features for optimization
    has_avx2_ = detectAVX2Support();
    if (has_avx2_) {
        Logger::info("NDI sender: AVX2 support detected for YUV conversions");
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
    ndi_frame.timecode = frame.timestamp_ns / 100;  // Convert to 100ns units
    
    // Handle YUYV format specially - convert to UYVY which NDI supports
    if (frame.fourcc == FOURCC_YUYV) {
        // YUYV to UYVY requires swapping Y and U/V bytes
        size_t buffer_size = frame.width * frame.height * 2;
        
        // Ensure buffer is allocated
        if (yuyv_to_uyvy_buffer_.size() < buffer_size) {
            yuyv_to_uyvy_buffer_.resize(buffer_size);
        }
        
        // Convert YUYV to UYVY with optimized byte swap
        const uint8_t* src = static_cast<const uint8_t*>(frame.data);
        uint8_t* dst = yuyv_to_uyvy_buffer_.data();
        
        if (has_avx2_ && frame.width % 16 == 0) {
            // AVX2 optimized conversion (process 32 pixels at once)
            convertYUYVtoUYVY_AVX2(src, dst, frame.width, frame.height);
        } else {
            // Scalar conversion
            convertYUYVtoUYVY_Scalar(src, dst, frame.width, frame.height);
        }
        
        ndi_frame.p_data = yuyv_to_uyvy_buffer_.data();
        ndi_frame.line_stride_in_bytes = frame.width * 2;
        ndi_frame.FourCC = NDIlib_FourCC_type_UYVY;
        
        // Log once for performance tracking
        if (!yuyv_conversion_logged_) {
            Logger::info("NDI sender: Using direct YUYV->UYVY conversion (zero-copy optimization)");
            yuyv_conversion_logged_ = true;
        }
    } else {
        // Direct passthrough for other formats
        ndi_frame.p_data = const_cast<uint8_t*>(static_cast<const uint8_t*>(frame.data));
        ndi_frame.line_stride_in_bytes = frame.stride;
        
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

void NdiSender::convertYUYVtoUYVY_Scalar(const uint8_t* src, uint8_t* dst, int width, int height) {
    // YUYV format: Y0 U0 Y1 V0 | Y2 U2 Y3 V2 | ...
    // UYVY format: U0 Y0 V0 Y1 | U2 Y2 V2 Y3 | ...
    size_t pixel_pairs = (width * height) / 2;
    
    for (size_t i = 0; i < pixel_pairs; ++i) {
        // Read YUYV
        uint8_t y0 = src[0];
        uint8_t u  = src[1];
        uint8_t y1 = src[2];
        uint8_t v  = src[3];
        
        // Write UYVY
        dst[0] = u;
        dst[1] = y0;
        dst[2] = v;
        dst[3] = y1;
        
        src += 4;
        dst += 4;
    }
}

void NdiSender::convertYUYVtoUYVY_AVX2(const uint8_t* src, uint8_t* dst, int width, int height) {
    // Process 32 pixels (64 bytes) at a time
    size_t total_bytes = width * height * 2;
    size_t avx_bytes = (total_bytes / 64) * 64;
    
    // Shuffle mask to convert YUYV to UYVY
    // YUYV: Y0 U0 Y1 V0 Y2 U2 Y3 V2 ... (indices 0,1,2,3,4,5,6,7...)
    // UYVY: U0 Y0 V0 Y1 U2 Y2 V2 Y3 ... (indices 1,0,3,2,5,4,7,6...)
    const __m256i shuffle_mask = _mm256_setr_epi8(
        1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14,
        1, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14
    );
    
    size_t i = 0;
    for (; i < avx_bytes; i += 64) {
        // Load 64 bytes (32 pixels in YUYV format)
        __m256i data0 = _mm256_loadu_si256((__m256i*)(src + i));
        __m256i data1 = _mm256_loadu_si256((__m256i*)(src + i + 32));
        
        // Shuffle to convert YUYV to UYVY
        __m256i result0 = _mm256_shuffle_epi8(data0, shuffle_mask);
        __m256i result1 = _mm256_shuffle_epi8(data1, shuffle_mask);
        
        // Store results
        _mm256_storeu_si256((__m256i*)(dst + i), result0);
        _mm256_storeu_si256((__m256i*)(dst + i + 32), result1);
    }
    
    // Handle remaining bytes with scalar code
    for (; i < total_bytes; i += 4) {
        uint8_t y0 = src[i];
        uint8_t u  = src[i + 1];
        uint8_t y1 = src[i + 2];
        uint8_t v  = src[i + 3];
        
        dst[i] = u;
        dst[i + 1] = y0;
        dst[i + 2] = v;
        dst[i + 3] = y1;
    }
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
