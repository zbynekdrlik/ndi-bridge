#pragma once

#include "display_output.h"
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <map>

namespace ndi_bridge {
namespace display {

class DRMDisplayOutput : public DisplayOutput {
public:
    DRMDisplayOutput();
    ~DRMDisplayOutput() override;
    
    bool initialize() override;
    void shutdown() override;
    
    std::vector<DisplayInfo> getDisplays() override;
    bool openDisplay(int display_id) override;
    void closeDisplay() override;
    
    bool isOpen() const override { return current_fb_ != 0; }
    DisplayInfo getCurrentDisplay() const override;
    
    bool displayFrame(const uint8_t* data, int width, int height, 
                     PixelFormat format, int stride) override;
    void clearDisplay() override;
    
private:
    struct DRMResources {
        int fd = -1;
        drmModeRes* resources = nullptr;
        drmModeConnector* connector = nullptr;
        drmModeEncoder* encoder = nullptr;
        drmModeCrtc* crtc = nullptr;
        drmModeCrtc* saved_crtc = nullptr;
        
        uint32_t connector_id = 0;
        uint32_t encoder_id = 0;
        uint32_t crtc_id = 0;
        
        void cleanup();
    };
    
    struct FrameBuffer {
        uint32_t fb_id = 0;
        uint32_t handle = 0;
        uint8_t* map = nullptr;
        size_t size = 0;
        int width = 0;
        int height = 0;
        int pitch = 0;
    };
    
    DRMResources drm_;
    std::map<int, DisplayInfo> displays_;
    DisplayInfo current_display_;
    
    // Double buffering
    FrameBuffer buffers_[2];
    int current_buffer_ = 0;
    uint32_t current_fb_ = 0;
    
    bool findCard();
    bool findConnector(int display_id);
    bool findEncoder();
    bool findCrtc();
    bool createFrameBuffers(int width, int height);
    void destroyFrameBuffers();
    bool setMode();
    void restoreMode();
    
    // Format conversion helpers
    void convertBGRAtoRGB(const uint8_t* src, uint8_t* dst, 
                         int width, int height, int src_stride, int dst_stride);
    void scaleFrame(const uint8_t* src, uint8_t* dst,
                   int src_width, int src_height, int src_stride,
                   int dst_width, int dst_height, int dst_stride);
};

} // namespace display
} // namespace ndi_bridge