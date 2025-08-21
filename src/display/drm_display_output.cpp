#include "display_output.h"
#include "../common/logger.h"
#include <fcntl.h>
#include <unistd.h>
#include <cstring>
#include <algorithm>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_fourcc.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <drm/drm.h>

namespace ndi_bridge {
namespace display {

// Hardware-accelerated DRM display with plane scaling
class DRMHWScaleDisplayOutput : public DisplayOutput {
public:
    DRMHWScaleDisplayOutput() = default;
    ~DRMHWScaleDisplayOutput() override {
        shutdown();
    }
    
    bool initialize() override {
        // Open DRM device
        const char* devices[] = {"/dev/dri/card0", "/dev/dri/card1"};
        for (const char* dev : devices) {
            drm_fd_ = open(dev, O_RDWR | O_CLOEXEC);
            if (drm_fd_ >= 0) {
                Logger::info("Opened DRM device: " + std::string(dev));
                break;
            }
        }
        
        if (drm_fd_ < 0) {
            Logger::error("Failed to open DRM device");
            return false;
        }
        
        // Become DRM master (required for mode setting)
        if (drmSetMaster(drm_fd_) < 0) {
            // Try the ioctl directly if the function is not available
            if (ioctl(drm_fd_, DRM_IOCTL_SET_MASTER, 0) < 0) {
                Logger::warning("Could not become DRM master - mode setting may fail");
                // Don't fail here as we might still work in some cases
            } else {
                Logger::info("Became DRM master via ioctl");
            }
        } else {
            Logger::info("Became DRM master");
        }
        
        // Check for required capabilities
        uint64_t has_dumb;
        if (drmGetCap(drm_fd_, DRM_CAP_DUMB_BUFFER, &has_dumb) < 0 || !has_dumb) {
            Logger::error("DRM device does not support dumb buffers");
            close(drm_fd_);
            drm_fd_ = -1;
            return false;
        }
        
        // Check for universal planes (required for scaling)
        if (drmSetClientCap(drm_fd_, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) < 0) {
            Logger::warning("Universal planes not supported - hardware scaling may not work");
            has_universal_planes_ = false;
        } else {
            has_universal_planes_ = true;
            Logger::info("Universal planes enabled for hardware scaling");
        }
        
        // Enable atomic mode setting if available (better for Intel GPUs)
        if (drmSetClientCap(drm_fd_, DRM_CLIENT_CAP_ATOMIC, 1) == 0) {
            has_atomic_ = true;
            Logger::info("Atomic mode setting enabled");
        } else {
            has_atomic_ = false;
            Logger::info("Using legacy mode setting");
        }
        
        // Get resources
        resources_ = drmModeGetResources(drm_fd_);
        if (!resources_) {
            Logger::error("Failed to get DRM resources");
            close(drm_fd_);
            drm_fd_ = -1;
            return false;
        }
        
        // Get plane resources for hardware scaling
        plane_resources_ = drmModeGetPlaneResources(drm_fd_);
        if (plane_resources_ && plane_resources_->count_planes > 0) {
            Logger::info("Found " + std::to_string(plane_resources_->count_planes) + " planes for hardware scaling");
        } else {
            Logger::warning("No planes found - hardware scaling not available");
        }
        
        // Find available displays
        findDisplays();
        
        return true;
    }
    
    void shutdown() override {
        closeDisplay();
        
        if (plane_resources_) {
            drmModeFreePlaneResources(plane_resources_);
            plane_resources_ = nullptr;
        }
        
        if (resources_) {
            drmModeFreeResources(resources_);
            resources_ = nullptr;
        }
        
        if (drm_fd_ >= 0) {
            // Drop DRM master before closing
            drmDropMaster(drm_fd_);
            close(drm_fd_);
            drm_fd_ = -1;
        }
    }
    
    std::vector<DisplayInfo> getDisplays() override {
        return displays_;
    }
    
    bool openDisplay(int display_id) override {
        if (display_id < 0 || display_id >= (int)displays_.size()) {
            Logger::error("Invalid display ID: " + std::to_string(display_id));
            return false;
        }
        
        closeDisplay();
        
        current_display_id_ = display_id;
        auto& disp = displays_[display_id];
        
        // Find connector
        connector_ = drmModeGetConnector(drm_fd_, disp.connector_id);
        if (!connector_ || connector_->connection != DRM_MODE_CONNECTED) {
            Logger::error("Display not connected");
            return false;
        }
        
        // Find encoder
        encoder_ = nullptr;
        if (connector_->encoder_id) {
            encoder_ = drmModeGetEncoder(drm_fd_, connector_->encoder_id);
        }
        
        if (!encoder_) {
            for (int i = 0; i < connector_->count_encoders; i++) {
                encoder_ = drmModeGetEncoder(drm_fd_, connector_->encoders[i]);
                if (encoder_) break;
            }
        }
        
        if (!encoder_) {
            Logger::error("No encoder found");
            drmModeFreeConnector(connector_);
            connector_ = nullptr;
            return false;
        }
        
        // Find CRTC
        crtc_id_ = 0;
        if (encoder_->crtc_id) {
            crtc_id_ = encoder_->crtc_id;
        } else {
            for (int i = 0; i < resources_->count_crtcs; i++) {
                if (encoder_->possible_crtcs & (1 << i)) {
                    crtc_id_ = resources_->crtcs[i];
                    break;
                }
            }
        }
        
        if (!crtc_id_) {
            Logger::error("No CRTC found");
            drmModeFreeEncoder(encoder_);
            drmModeFreeConnector(connector_);
            encoder_ = nullptr;
            connector_ = nullptr;
            return false;
        }
        
        // Save current CRTC for restoration
        saved_crtc_ = drmModeGetCrtc(drm_fd_, crtc_id_);
        
        // Get preferred mode
        mode_ = nullptr;
        for (int i = 0; i < connector_->count_modes; i++) {
            if (connector_->modes[i].type & DRM_MODE_TYPE_PREFERRED) {
                mode_ = &connector_->modes[i];
                break;
            }
        }
        
        if (!mode_ && connector_->count_modes > 0) {
            mode_ = &connector_->modes[0];
        }
        
        if (!mode_) {
            Logger::error("No mode found");
            cleanup();
            return false;
        }
        
        // Update display info with actual mode
        disp.width = mode_->hdisplay;
        disp.height = mode_->vdisplay;
        disp.refresh_rate = mode_->vrefresh;
        
        Logger::info("Display mode: " + std::to_string(mode_->hdisplay) + "x" + 
                    std::to_string(mode_->vdisplay) + "@" + std::to_string(mode_->vrefresh) + "Hz");
        
        // Find a plane that can be used with this CRTC for scaling
        if (plane_resources_ && has_universal_planes_) {
            findScalingPlane();
        }
        
        // Create framebuffers for double buffering
        if (!createFramebuffers()) {
            cleanup();
            return false;
        }
        
        // Set initial mode with black screen
        clearDisplay();
        if (drmModeSetCrtc(drm_fd_, crtc_id_, fb_[current_fb_].fb_id, 0, 0,
                          &connector_->connector_id, 1, mode_) < 0) {
            Logger::error("Failed to set mode");
            cleanup();
            return false;
        }
        
        return true;
    }
    
    void closeDisplay() override {
        cleanup();
        current_display_id_ = -1;
    }
    
    bool isOpen() const override {
        return connector_ != nullptr;
    }
    
    DisplayInfo getCurrentDisplay() const override {
        if (current_display_id_ >= 0 && current_display_id_ < (int)displays_.size()) {
            return displays_[current_display_id_];
        }
        return DisplayInfo();
    }
    
    bool displayFrame(const uint8_t* data, int width, int height, 
                     PixelFormat format, int stride) override {
        if (!connector_ || !mode_) {
            return false;
        }
        
        // Get next framebuffer
        int next_fb = current_fb_ ^ 1;
        auto& fb = fb_[next_fb];
        
        if (!fb.map) {
            return false;
        }
        
        // Check if we can use hardware scaling
        if (plane_id_ && has_universal_planes_) {
            // Use hardware plane scaling
            return displayFrameWithHWScaling(data, width, height, format, stride, next_fb);
        } else {
            // Fall back to software scaling
            return displayFrameWithSWScaling(data, width, height, format, stride, next_fb);
        }
    }
    
    void clearDisplay() override {
        for (int i = 0; i < 2; i++) {
            if (fb_[i].map) {
                memset(fb_[i].map, 0, fb_[i].size);
            }
        }
    }
    
private:
    int drm_fd_ = -1;
    drmModeRes* resources_ = nullptr;
    drmModePlaneRes* plane_resources_ = nullptr;
    drmModeConnector* connector_ = nullptr;
    drmModeEncoder* encoder_ = nullptr;
    drmModeCrtc* saved_crtc_ = nullptr;
    drmModeModeInfo* mode_ = nullptr;
    uint32_t crtc_id_ = 0;
    uint32_t plane_id_ = 0;
    bool has_universal_planes_ = false;
    bool has_atomic_ = false;
    
    std::vector<DisplayInfo> displays_;
    
    struct Framebuffer {
        uint32_t fb_id = 0;
        uint32_t handle = 0;
        uint8_t* map = nullptr;
        size_t size = 0;
        uint32_t pitch = 0;
        uint32_t width = 0;
        uint32_t height = 0;
    };
    
    Framebuffer fb_[2]; // Double buffering
    Framebuffer source_fb_[2]; // Source framebuffers at original resolution for HW scaling
    int current_fb_ = 0;
    
    void findDisplays() {
        displays_.clear();
        
        for (int i = 0; i < resources_->count_connectors && displays_.size() < 3; i++) {
            drmModeConnector* conn = drmModeGetConnector(drm_fd_, resources_->connectors[i]);
            if (!conn) continue;
            
            DisplayInfo info;
            info.id = displays_.size();
            info.connector_id = conn->connector_id;
            
            // Get connector name
            const char* types[] = {"Unknown", "VGA", "DVI-I", "DVI-D", "DVI-A",
                                  "Composite", "S-Video", "LVDS", "Component", "DIN",
                                  "DisplayPort", "HDMI-A", "HDMI-B", "TV", "eDP", "DSI"};
            if (conn->connector_type < sizeof(types)/sizeof(types[0])) {
                info.connector = types[conn->connector_type];
            } else {
                info.connector = "Unknown";
            }
            info.connector += "-" + std::to_string(conn->connector_type_id);
            
            info.connected = (conn->connection == DRM_MODE_CONNECTED);
            
            if (info.connected && conn->count_modes > 0) {
                for (int j = 0; j < conn->count_modes; j++) {
                    if (conn->modes[j].type & DRM_MODE_TYPE_PREFERRED) {
                        info.width = conn->modes[j].hdisplay;
                        info.height = conn->modes[j].vdisplay;
                        info.refresh_rate = conn->modes[j].vrefresh;
                        break;
                    }
                }
                if (info.width == 0 && conn->count_modes > 0) {
                    info.width = conn->modes[0].hdisplay;
                    info.height = conn->modes[0].vdisplay;
                    info.refresh_rate = conn->modes[0].vrefresh;
                }
            }
            
            displays_.push_back(info);
            drmModeFreeConnector(conn);
        }
    }
    
    void findScalingPlane() {
        plane_id_ = 0;
        
        if (!plane_resources_) return;
        
        // Find a plane that supports our CRTC and can do scaling
        for (uint32_t i = 0; i < plane_resources_->count_planes; i++) {
            drmModePlane* plane = drmModeGetPlane(drm_fd_, plane_resources_->planes[i]);
            if (!plane) continue;
            
            // Check if plane can be used with our CRTC
            if (!(plane->possible_crtcs & (1 << getCrtcIndex()))) {
                drmModeFreePlane(plane);
                continue;
            }
            
            // Check plane properties for scaling support
            drmModeObjectProperties* props = drmModeObjectGetProperties(
                drm_fd_, plane->plane_id, DRM_MODE_OBJECT_PLANE);
            
            if (props) {
                bool supports_scaling = false;
                
                // Look for scaling-related properties
                for (uint32_t j = 0; j < props->count_props; j++) {
                    drmModePropertyRes* prop = drmModeGetProperty(drm_fd_, props->props[j]);
                    if (prop) {
                        // Intel GPUs typically support scaling on overlay planes
                        if (strcmp(prop->name, "type") == 0) {
                            uint64_t value = props->prop_values[j];
                            // DRM_PLANE_TYPE_OVERLAY = 0, DRM_PLANE_TYPE_PRIMARY = 1
                            if (value == 0 || value == 1) {
                                supports_scaling = true;
                            }
                        }
                        drmModeFreeProperty(prop);
                    }
                }
                
                if (supports_scaling) {
                    plane_id_ = plane->plane_id;
                    Logger::info("Found plane " + std::to_string(plane_id_) + " with scaling support");
                    drmModeFreeObjectProperties(props);
                    drmModeFreePlane(plane);
                    break;
                }
                
                drmModeFreeObjectProperties(props);
            }
            
            drmModeFreePlane(plane);
        }
        
        if (!plane_id_) {
            Logger::warning("No plane with scaling support found - will use software scaling");
        }
    }
    
    int getCrtcIndex() {
        for (int i = 0; i < resources_->count_crtcs; i++) {
            if (resources_->crtcs[i] == crtc_id_) {
                return i;
            }
        }
        return -1;
    }
    
    bool createFramebuffers() {
        // Create display framebuffers at display resolution
        for (int i = 0; i < 2; i++) {
            struct drm_mode_create_dumb create_req = {};  // Zero-initialize
            create_req.width = mode_->hdisplay;
            create_req.height = mode_->vdisplay;
            create_req.bpp = 32;
            
            if (drmIoctl(drm_fd_, DRM_IOCTL_MODE_CREATE_DUMB, &create_req) < 0) {
                Logger::error("Failed to create dumb buffer");
                // Clean up previously created buffers
                for (int j = 0; j < i; j++) {
                    if (fb_[j].handle) {
                        struct drm_mode_destroy_dumb destroy_req = {};
                        destroy_req.handle = fb_[j].handle;
                        drmIoctl(drm_fd_, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy_req);
                        fb_[j].handle = 0;
                    }
                }
                return false;
            }
            
            fb_[i].handle = create_req.handle;
            fb_[i].pitch = create_req.pitch;
            fb_[i].size = create_req.size;
            fb_[i].width = mode_->hdisplay;
            fb_[i].height = mode_->vdisplay;
            
            if (drmModeAddFB(drm_fd_, mode_->hdisplay, mode_->vdisplay, 24, 32,
                            fb_[i].pitch, fb_[i].handle, &fb_[i].fb_id) < 0) {
                Logger::error("Failed to create framebuffer");
                // Clean up all created buffers including current one
                for (int j = 0; j <= i; j++) {
                    if (fb_[j].handle) {
                        struct drm_mode_destroy_dumb destroy_req = {};
                        destroy_req.handle = fb_[j].handle;
                        drmIoctl(drm_fd_, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy_req);
                        fb_[j].handle = 0;
                    }
                }
                return false;
            }
            
            struct drm_mode_map_dumb map_req = {};
            map_req.handle = fb_[i].handle;
            
            if (drmIoctl(drm_fd_, DRM_IOCTL_MODE_MAP_DUMB, &map_req) < 0) {
                Logger::error("Failed to map dumb buffer");
                // Clean up all created buffers including current one
                for (int j = 0; j <= i; j++) {
                    if (fb_[j].fb_id) {
                        drmModeRmFB(drm_fd_, fb_[j].fb_id);
                        fb_[j].fb_id = 0;
                    }
                    if (fb_[j].handle) {
                        struct drm_mode_destroy_dumb destroy_req = {};
                        destroy_req.handle = fb_[j].handle;
                        drmIoctl(drm_fd_, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy_req);
                        fb_[j].handle = 0;
                    }
                }
                return false;
            }
            
            fb_[i].map = (uint8_t*)mmap(0, fb_[i].size, PROT_READ | PROT_WRITE,
                                       MAP_SHARED, drm_fd_, map_req.offset);
            
            if (fb_[i].map == MAP_FAILED) {
                Logger::error("Failed to mmap framebuffer");
                fb_[i].map = nullptr;
                // Clean up all created buffers including current one
                for (int j = 0; j <= i; j++) {
                    if (fb_[j].map && fb_[j].map != MAP_FAILED) {
                        munmap(fb_[j].map, fb_[j].size);
                        fb_[j].map = nullptr;
                    }
                    if (fb_[j].fb_id) {
                        drmModeRmFB(drm_fd_, fb_[j].fb_id);
                        fb_[j].fb_id = 0;
                    }
                    if (fb_[j].handle) {
                        struct drm_mode_destroy_dumb destroy_req = {};
                        destroy_req.handle = fb_[j].handle;
                        drmIoctl(drm_fd_, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy_req);
                        fb_[j].handle = 0;
                    }
                }
                return false;
            }
        }
        
        return true;
    }
    
    bool createSourceFramebuffer(int width, int height, int index) {
        // Create source framebuffer at NDI stream resolution
        if (source_fb_[index].width == (uint32_t)width && 
            source_fb_[index].height == (uint32_t)height) {
            return true; // Already created at this resolution
        }
        
        // Clean up old buffer if exists
        if (source_fb_[index].map) {
            munmap(source_fb_[index].map, source_fb_[index].size);
            source_fb_[index].map = nullptr;
        }
        if (source_fb_[index].fb_id) {
            drmModeRmFB(drm_fd_, source_fb_[index].fb_id);
            source_fb_[index].fb_id = 0;
        }
        if (source_fb_[index].handle) {
            struct drm_mode_destroy_dumb destroy_req = {};
            destroy_req.handle = source_fb_[index].handle;
            drmIoctl(drm_fd_, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy_req);
            source_fb_[index].handle = 0;
        }
        
        // Create new buffer
        struct drm_mode_create_dumb create_req = {};
        create_req.width = width;
        create_req.height = height;
        create_req.bpp = 32;
        
        if (drmIoctl(drm_fd_, DRM_IOCTL_MODE_CREATE_DUMB, &create_req) < 0) {
            Logger::error("Failed to create source dumb buffer");
            return false;
        }
        
        source_fb_[index].handle = create_req.handle;
        source_fb_[index].pitch = create_req.pitch;
        source_fb_[index].size = create_req.size;
        source_fb_[index].width = width;
        source_fb_[index].height = height;
        
        if (drmModeAddFB(drm_fd_, width, height, 24, 32,
                        source_fb_[index].pitch, source_fb_[index].handle, 
                        &source_fb_[index].fb_id) < 0) {
            Logger::error("Failed to create source framebuffer");
            return false;
        }
        
        struct drm_mode_map_dumb map_req = {};
        map_req.handle = source_fb_[index].handle;
        
        if (drmIoctl(drm_fd_, DRM_IOCTL_MODE_MAP_DUMB, &map_req) < 0) {
            Logger::error("Failed to map source dumb buffer");
            return false;
        }
        
        source_fb_[index].map = (uint8_t*)mmap(0, source_fb_[index].size, 
                                              PROT_READ | PROT_WRITE,
                                              MAP_SHARED, drm_fd_, map_req.offset);
        
        if (source_fb_[index].map == MAP_FAILED) {
            Logger::error("Failed to mmap source framebuffer");
            source_fb_[index].map = nullptr;
            return false;
        }
        
        return true;
    }
    
    bool displayFrameWithHWScaling(const uint8_t* data, int width, int height,
                                   PixelFormat format, int stride, int next_fb) {
        // Create source framebuffer at NDI resolution
        if (!createSourceFramebuffer(width, height, next_fb)) {
            Logger::error("Failed to create source framebuffer for HW scaling");
            return displayFrameWithSWScaling(data, width, height, format, stride, next_fb);
        }
        
        auto& src_fb = source_fb_[next_fb];
        
        // Copy data to source framebuffer (no scaling, just format conversion)
        convertToFramebuffer(data, width, height, format, stride, 
                           src_fb.map, src_fb.pitch, width, height);
        
        // Calculate scaling parameters to preserve aspect ratio
        float src_aspect = (float)width / height;
        float dst_aspect = (float)mode_->hdisplay / mode_->vdisplay;
        
        int scaled_width, scaled_height;
        int x_offset = 0, y_offset = 0;
        
        if (src_aspect > dst_aspect) {
            scaled_width = mode_->hdisplay;
            scaled_height = mode_->hdisplay / src_aspect;
            y_offset = (mode_->vdisplay - scaled_height) / 2;
        } else {
            scaled_height = mode_->vdisplay;
            scaled_width = mode_->vdisplay * src_aspect;
            x_offset = (mode_->hdisplay - scaled_width) / 2;
        }
        
        // Use DRM plane to scale and display the source framebuffer
        if (drmModeSetPlane(drm_fd_, plane_id_, crtc_id_, src_fb.fb_id, 0,
                           x_offset, y_offset, scaled_width, scaled_height,  // Destination (CRTC)
                           0, 0, width << 16, height << 16) < 0) {          // Source (FB)
            Logger::error("Hardware scaling failed, falling back to software");
            return displayFrameWithSWScaling(data, width, height, format, stride, next_fb);
        }
        
        current_fb_ = next_fb;
        return true;
    }
    
    bool displayFrameWithSWScaling(const uint8_t* data, int width, int height,
                                   PixelFormat format, int stride, int next_fb) {
        auto& fb = fb_[next_fb];
        
        // Clear framebuffer first (for letterboxing)
        memset(fb.map, 0, fb.size);
        
        // Calculate scaling to fit display while preserving aspect ratio
        float src_aspect = (float)width / height;
        float dst_aspect = (float)mode_->hdisplay / mode_->vdisplay;
        
        int scaled_width, scaled_height;
        int x_offset = 0, y_offset = 0;
        
        if (src_aspect > dst_aspect) {
            scaled_width = mode_->hdisplay;
            scaled_height = mode_->hdisplay / src_aspect;
            y_offset = (mode_->vdisplay - scaled_height) / 2;
        } else {
            scaled_height = mode_->vdisplay;
            scaled_width = mode_->vdisplay * src_aspect;
            x_offset = (mode_->hdisplay - scaled_width) / 2;
        }
        
        // Software scaling with format conversion
        convertToFramebuffer(data, width, height, format, stride,
                           fb.map + (y_offset * fb.pitch) + (x_offset * 4),
                           fb.pitch, scaled_width, scaled_height);
        
        // Page flip to display the new frame
        if (drmModePageFlip(drm_fd_, crtc_id_, fb.fb_id, 
                           DRM_MODE_PAGE_FLIP_EVENT, nullptr) < 0) {
            drmModeSetCrtc(drm_fd_, crtc_id_, fb.fb_id, 0, 0,
                          &connector_->connector_id, 1, mode_);
        } else {
            drmEventContext evctx = {};
            evctx.version = DRM_EVENT_CONTEXT_VERSION;
            evctx.page_flip_handler = [](int, unsigned int, unsigned int, 
                                        unsigned int, void*) {};
            
            fd_set fds;
            FD_ZERO(&fds);
            FD_SET(drm_fd_, &fds);
            
            struct timeval tv = {0, 16667}; // ~60fps timeout
            if (select(drm_fd_ + 1, &fds, nullptr, nullptr, &tv) > 0) {
                drmHandleEvent(drm_fd_, &evctx);
            }
        }
        
        current_fb_ = next_fb;
        return true;
    }
    
    void convertToFramebuffer(const uint8_t* src_data, int src_width, int src_height,
                             PixelFormat format, int src_stride,
                             uint8_t* dst_data, int dst_pitch, 
                             int dst_width, int dst_height) {
        // Simple bilinear scaling with format conversion
        for (int dst_y = 0; dst_y < dst_height; dst_y++) {
            int src_y = (dst_y * src_height) / dst_height;
            if (src_y >= src_height) src_y = src_height - 1;
            
            uint8_t* dst_row = dst_data + (dst_y * dst_pitch);
            
            for (int dst_x = 0; dst_x < dst_width; dst_x++) {
                int src_x = (dst_x * src_width) / dst_width;
                if (src_x >= src_width) src_x = src_width - 1;
                
                if (format == PixelFormat::BGRA) {
                    const uint8_t* src_pixel = src_data + (src_y * src_stride) + (src_x * 4);
                    uint8_t* dst_pixel = dst_row + (dst_x * 4);
                    
                    // Convert BGRA to XRGB8888
                    dst_pixel[0] = src_pixel[0]; // B
                    dst_pixel[1] = src_pixel[1]; // G
                    dst_pixel[2] = src_pixel[2]; // R
                    dst_pixel[3] = 0xFF;          // X
                } else if (format == PixelFormat::UYVY) {
                    int src_x_pair = (src_x / 2) * 2;
                    // Ensure we don't read past buffer boundary
                    if (src_x_pair * 2 + 3 >= src_stride) continue;
                    const uint8_t* src = src_data + (src_y * src_stride) + (src_x_pair * 2);
                    uint8_t* dst_pixel = dst_row + (dst_x * 4);
                    
                    uint8_t y = (src_x & 1) ? src[3] : src[1];
                    uint8_t u = src[0];
                    uint8_t v = src[2];
                    
                    // YUV to RGB conversion (BT.601)
                    int c = y - 16;
                    int d = u - 128;
                    int e = v - 128;
                    
                    int r = (298 * c + 409 * e + 128) >> 8;
                    int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
                    int b = (298 * c + 516 * d + 128) >> 8;
                    
                    dst_pixel[0] = std::min(255, std::max(0, b));
                    dst_pixel[1] = std::min(255, std::max(0, g));
                    dst_pixel[2] = std::min(255, std::max(0, r));
                    dst_pixel[3] = 0xFF;
                }
            }
        }
    }
    
    void cleanup() {
        // Restore saved CRTC if exists
        if (saved_crtc_ && crtc_id_ && connector_) {
            uint32_t conn_id = connector_->connector_id;
            drmModeSetCrtc(drm_fd_, saved_crtc_->crtc_id, saved_crtc_->buffer_id,
                          saved_crtc_->x, saved_crtc_->y, &conn_id, 1,
                          &saved_crtc_->mode);
            drmModeFreeCrtc(saved_crtc_);
            saved_crtc_ = nullptr;
        }
        
        // Clean up framebuffers
        for (int i = 0; i < 2; i++) {
            // Display framebuffers
            if (fb_[i].map) {
                munmap(fb_[i].map, fb_[i].size);
                fb_[i].map = nullptr;
            }
            if (fb_[i].fb_id) {
                drmModeRmFB(drm_fd_, fb_[i].fb_id);
                fb_[i].fb_id = 0;
            }
            if (fb_[i].handle) {
                struct drm_mode_destroy_dumb destroy_req = {};
                destroy_req.handle = fb_[i].handle;
                drmIoctl(drm_fd_, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy_req);
                fb_[i].handle = 0;
            }
            
            // Source framebuffers for HW scaling
            if (source_fb_[i].map) {
                munmap(source_fb_[i].map, source_fb_[i].size);
                source_fb_[i].map = nullptr;
            }
            if (source_fb_[i].fb_id) {
                drmModeRmFB(drm_fd_, source_fb_[i].fb_id);
                source_fb_[i].fb_id = 0;
            }
            if (source_fb_[i].handle) {
                struct drm_mode_destroy_dumb destroy_req = {};
                destroy_req.handle = source_fb_[i].handle;
                drmIoctl(drm_fd_, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy_req);
                source_fb_[i].handle = 0;
            }
        }
        
        if (encoder_) {
            drmModeFreeEncoder(encoder_);
            encoder_ = nullptr;
        }
        
        if (connector_) {
            drmModeFreeConnector(connector_);
            connector_ = nullptr;
        }
        
        mode_ = nullptr;
        crtc_id_ = 0;
        plane_id_ = 0;
    }
};

// Factory function for DRM display output
std::unique_ptr<DisplayOutput> createDRMDisplayOutput() {
    // Don't initialize here - let the caller do it to avoid double initialization
    return std::make_unique<DRMHWScaleDisplayOutput>();
}

} // namespace display
} // namespace ndi_bridge