// capture_interface.h
#pragma once

#include <string>
#include <vector>
#include <memory>
#include <functional>
#include <cstdint>

namespace ndi_bridge {

/**
 * @brief Interface for video capture implementations
 * 
 * This abstract interface defines the contract for video capture devices
 * used in the NDI Bridge application.
 * 
 * Version: 1.0.1
 */
class ICaptureDevice {
public:
    /**
     * @brief Device information structure
     */
    struct DeviceInfo {
        std::string id;        // Unique device identifier
        std::string name;      // Human-readable device name
    };

    /**
     * @brief Video format information
     */
    struct VideoFormat {
        int width;
        int height;
        int stride;
        std::string pixel_format;  // e.g., "UYVY", "YUY2", "NV12", "BGRA"
        uint32_t fps_numerator;
        uint32_t fps_denominator;
    };

    /**
     * @brief Frame callback function type
     * @param data Frame data pointer
     * @param size Frame size in bytes
     * @param timestamp Frame timestamp in nanoseconds
     * @param format Video format information
     */
    using FrameCallback = std::function<void(const void* data, size_t size, 
                                           int64_t timestamp, const VideoFormat& format)>;

    /**
     * @brief Error callback function type
     * @param error Error message
     */
    using ErrorCallback = std::function<void(const std::string& error)>;

    virtual ~ICaptureDevice() = default;
    
    /**
     * @brief Enumerate available capture devices
     * @return Vector of device information
     */
    virtual std::vector<DeviceInfo> enumerateDevices() = 0;
    
    /**
     * @brief Start capture with specified device
     * @param device_name Device name (empty for default device)
     * @return true if capture started successfully
     */
    virtual bool startCapture(const std::string& device_name = "") = 0;
    
    /**
     * @brief Stop capture
     */
    virtual void stopCapture() = 0;
    
    /**
     * @brief Check if currently capturing
     * @return true if capturing
     */
    virtual bool isCapturing() const = 0;
    
    /**
     * @brief Set frame callback
     * @param callback Function to call when frame is available
     */
    virtual void setFrameCallback(FrameCallback callback) = 0;
    
    /**
     * @brief Set error callback
     * @param callback Function to call on error
     */
    virtual void setErrorCallback(ErrorCallback callback) = 0;
    
    /**
     * @brief Check if device has encountered an error
     * @return true if device has error
     */
    virtual bool hasError() const = 0;
    
    /**
     * @brief Get last error message
     * @return Error message string
     */
    virtual std::string getLastError() const = 0;
};

} // namespace ndi_bridge
