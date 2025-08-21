#pragma once

#include <string>
#include <memory>
#include <vector>
#include <cstdint>

namespace ndi_bridge {
namespace display {

// Display information
struct DisplayInfo {
    int id;                    // Display ID (0, 1, 2)
    std::string connector;     // e.g., "HDMI-A-1"
    int width;
    int height;
    float refresh_rate;
    bool connected;
    bool active;
    uint32_t connector_id = 0; // DRM connector ID (for DRM/KMS)
};

// Frame format
enum class PixelFormat {
    BGRA,    // 32-bit BGRA (NDI native)
    RGB24,   // 24-bit RGB
    UYVY,    // YUV 4:2:2
    NV12     // YUV 4:2:0 planar
};

class DisplayOutput {
public:
    DisplayOutput();
    virtual ~DisplayOutput();
    
    // Initialize display system
    virtual bool initialize() = 0;
    
    // Shutdown display system
    virtual void shutdown() = 0;
    
    // Get list of available displays
    virtual std::vector<DisplayInfo> getDisplays() = 0;
    
    // Open a specific display for output
    virtual bool openDisplay(int display_id) = 0;
    
    // Close the display
    virtual void closeDisplay() = 0;
    
    // Check if display is open
    virtual bool isOpen() const = 0;
    
    // Get current display info
    virtual DisplayInfo getCurrentDisplay() const = 0;
    
    // Display a frame
    virtual bool displayFrame(const uint8_t* data, int width, int height, 
                             PixelFormat format, int stride) = 0;
    
    // Clear display (show black)
    virtual void clearDisplay() = 0;
    
protected:
    int current_display_id_ = -1;
};

// Factory function to create appropriate display output
std::unique_ptr<DisplayOutput> createDisplayOutput();

} // namespace display
} // namespace ndi_bridge