#include "display_output.h"

namespace ndi_bridge {
namespace display {

// Base class implementations
DisplayOutput::DisplayOutput() = default;
DisplayOutput::~DisplayOutput() = default;

// Simple framebuffer implementation for initial testing
class FramebufferDisplayOutput : public DisplayOutput {
public:
    FramebufferDisplayOutput() = default;
    ~FramebufferDisplayOutput() override = default;
    
    bool initialize() override {
        // TODO: Implement framebuffer initialization
        return true;
    }
    
    void shutdown() override {
        // TODO: Implement shutdown
    }
    
    std::vector<DisplayInfo> getDisplays() override {
        std::vector<DisplayInfo> displays;
        
        // Return dummy displays for now
        for (int i = 0; i < 3; i++) {
            DisplayInfo info;
            info.id = i;
            info.connector = "HDMI-" + std::to_string(i + 1);
            info.width = 1920;
            info.height = 1080;
            info.refresh_rate = 60.0f;
            info.connected = true;
            info.active = false;
            displays.push_back(info);
        }
        
        return displays;
    }
    
    bool openDisplay(int display_id) override {
        current_display_id_ = display_id;
        // TODO: Actually open framebuffer device
        return true;
    }
    
    void closeDisplay() override {
        current_display_id_ = -1;
        // TODO: Close framebuffer
    }
    
    bool isOpen() const override {
        return current_display_id_ >= 0;
    }
    
    DisplayInfo getCurrentDisplay() const override {
        DisplayInfo info;
        info.id = current_display_id_;
        info.connector = "HDMI-" + std::to_string(current_display_id_ + 1);
        info.width = 1920;
        info.height = 1080;
        info.refresh_rate = 60.0f;
        info.connected = true;
        info.active = true;
        return info;
    }
    
    bool displayFrame(const uint8_t* data, int width, int height, 
                     PixelFormat format, int stride) override {
        // TODO: Implement actual frame display
        // For now, just return success
        return true;
    }
    
    void clearDisplay() override {
        // TODO: Clear the display
    }
};

// Factory function
std::unique_ptr<DisplayOutput> createDisplayOutput() {
#ifdef __linux__
    // For now, use simple framebuffer implementation
    // Later we can switch to DRM/KMS for better performance
    return std::make_unique<FramebufferDisplayOutput>();
#else
    // Windows or other platforms not supported yet
    return nullptr;
#endif
}

} // namespace display
} // namespace ndi_bridge