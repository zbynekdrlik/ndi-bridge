// v4l2_device_enumerator.h
#pragma once

#include <string>
#include <vector>
#include <linux/videodev2.h>

namespace ndi_bridge {
namespace v4l2 {

/**
 * @brief Device information structure
 */
struct V4L2DeviceInfo {
    std::string path;        // Device path (e.g., "/dev/video0")
    std::string name;        // Device name from driver
    std::string driver;      // Driver name
    std::string bus_info;    // Bus information
    uint32_t capabilities;   // Device capabilities
    
    // Check if device supports video capture
    bool supportsCapture() const {
        return (capabilities & V4L2_CAP_VIDEO_CAPTURE) != 0;
    }
    
    // Check if device supports streaming
    bool supportsStreaming() const {
        return (capabilities & V4L2_CAP_STREAMING) != 0;
    }
};

/**
 * @brief Enumerates V4L2 video capture devices
 * 
 * Version: 1.3.0
 */
class V4L2DeviceEnumerator {
public:
    /**
     * @brief Enumerate all V4L2 devices
     * @return Vector of device information
     */
    static std::vector<V4L2DeviceInfo> enumerateDevices();
    
    /**
     * @brief Get device information for a specific device
     * @param device_path Device path (e.g., "/dev/video0")
     * @return Device information, or empty struct if failed
     */
    static V4L2DeviceInfo getDeviceInfo(const std::string& device_path);
    
    /**
     * @brief Find device by name
     * @param name Device name to search for
     * @return Device path if found, empty string otherwise
     */
    static std::string findDeviceByName(const std::string& name);
    
private:
    /**
     * @brief Query device capabilities
     * @param fd File descriptor
     * @param info Device info to fill
     * @return true if successful
     */
    static bool queryDeviceCapabilities(int fd, V4L2DeviceInfo& info);
    
    /**
     * @brief Check if path is a V4L2 device
     * @param path Device path
     * @return true if it's a valid V4L2 device
     */
    static bool isV4L2Device(const std::string& path);
};

} // namespace v4l2
} // namespace ndi_bridge
