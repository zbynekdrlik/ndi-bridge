// v4l2_device_enumerator.cpp
#include "v4l2_device_enumerator.h"
#include "../../common/logger.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <dirent.h>
#include <cstring>
#include <algorithm>

namespace ndi_bridge {
namespace v4l2 {

std::vector<V4L2DeviceInfo> V4L2DeviceEnumerator::enumerateDevices() {
    std::vector<V4L2DeviceInfo> devices;
    
    DIR* dir = opendir("/dev");
    if (!dir) {
        Logger::log("V4L2DeviceEnumerator: Failed to open /dev directory");
        return devices;
    }
    
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        std::string name = entry->d_name;
        
        // Check if it's a video device
        if (name.find("video") == 0) {
            std::string path = "/dev/" + name;
            
            if (isV4L2Device(path)) {
                V4L2DeviceInfo info = getDeviceInfo(path);
                if (!info.path.empty()) {
                    devices.push_back(info);
                }
            }
        }
    }
    
    closedir(dir);
    
    // Sort by device path
    std::sort(devices.begin(), devices.end(), 
              [](const V4L2DeviceInfo& a, const V4L2DeviceInfo& b) {
                  return a.path < b.path;
              });
    
    Logger::log("V4L2DeviceEnumerator: Found " + std::to_string(devices.size()) + " devices");
    return devices;
}

V4L2DeviceInfo V4L2DeviceEnumerator::getDeviceInfo(const std::string& device_path) {
    V4L2DeviceInfo info;
    
    int fd = open(device_path.c_str(), O_RDWR | O_NONBLOCK);
    if (fd < 0) {
        return info;
    }
    
    info.path = device_path;
    
    if (!queryDeviceCapabilities(fd, info)) {
        close(fd);
        return V4L2DeviceInfo(); // Return empty info
    }
    
    close(fd);
    return info;
}

std::string V4L2DeviceEnumerator::findDeviceByName(const std::string& name) {
    auto devices = enumerateDevices();
    
    // Convert search name to lowercase for case-insensitive search
    std::string search_name = name;
    std::transform(search_name.begin(), search_name.end(), search_name.begin(), ::tolower);
    
    for (const auto& device : devices) {
        std::string device_name = device.name;
        std::transform(device_name.begin(), device_name.end(), device_name.begin(), ::tolower);
        
        if (device_name.find(search_name) != std::string::npos) {
            return device.path;
        }
        
        // Also check bus info
        std::string bus_info = device.bus_info;
        std::transform(bus_info.begin(), bus_info.end(), bus_info.begin(), ::tolower);
        
        if (bus_info.find(search_name) != std::string::npos) {
            return device.path;
        }
    }
    
    return "";
}

bool V4L2DeviceEnumerator::queryDeviceCapabilities(int fd, V4L2DeviceInfo& info) {
    v4l2_capability caps;
    memset(&caps, 0, sizeof(caps));
    
    if (ioctl(fd, VIDIOC_QUERYCAP, &caps) < 0) {
        return false;
    }
    
    info.name = reinterpret_cast<const char*>(caps.card);
    info.driver = reinterpret_cast<const char*>(caps.driver);
    info.bus_info = reinterpret_cast<const char*>(caps.bus_info);
    info.capabilities = caps.capabilities;
    
    // If device has device_caps, use those instead
    if (caps.capabilities & V4L2_CAP_DEVICE_CAPS) {
        info.capabilities = caps.device_caps;
    }
    
    return true;
}

bool V4L2DeviceEnumerator::isV4L2Device(const std::string& path) {
    int fd = open(path.c_str(), O_RDWR | O_NONBLOCK);
    if (fd < 0) {
        return false;
    }
    
    v4l2_capability caps;
    memset(&caps, 0, sizeof(caps));
    
    bool is_v4l2 = (ioctl(fd, VIDIOC_QUERYCAP, &caps) == 0);
    
    close(fd);
    return is_v4l2;
}

} // namespace v4l2
} // namespace ndi_bridge
