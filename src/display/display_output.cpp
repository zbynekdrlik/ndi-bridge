#include "display_output.h"
#include "../common/logger.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/fb.h>
#include <cstring>
#include <algorithm>

namespace ndi_bridge {
namespace display {

// Base class implementations
DisplayOutput::DisplayOutput() = default;
DisplayOutput::~DisplayOutput() = default;

// Simple framebuffer implementation for Linux console
class FramebufferDisplayOutput : public DisplayOutput {
public:
    FramebufferDisplayOutput() = default;
    ~FramebufferDisplayOutput() override {
        if (fb_mapped_) {
            shutdown();
        }
    }
    
    bool initialize() override {
        // Framebuffer devices are opened per-display in openDisplay()
        return true;
    }
    
    void shutdown() override {
        closeDisplay();
    }
    
    std::vector<DisplayInfo> getDisplays() override {
        std::vector<DisplayInfo> displays;
        
        // Check for available framebuffer devices
        for (int i = 0; i < 3; i++) {
            DisplayInfo info;
            info.id = i;
            info.connector = "HDMI-" + std::to_string(i + 1);
            
            // Try to open framebuffer to check if it exists
            std::string fb_path = "/dev/fb" + std::to_string(i);
            int fd = open(fb_path.c_str(), O_RDWR);
            if (fd >= 0) {
                struct fb_var_screeninfo vinfo;
                if (ioctl(fd, FBIOGET_VSCREENINFO, &vinfo) == 0) {
                    info.width = vinfo.xres;
                    info.height = vinfo.yres;
                    info.refresh_rate = 60.0f; // Estimate
                    info.connected = true;
                } else {
                    info.width = 1920;
                    info.height = 1080;
                    info.refresh_rate = 60.0f;
                    info.connected = false;
                }
                close(fd);
            } else {
                // Assume default resolution if can't open
                info.width = 1920;
                info.height = 1080;
                info.refresh_rate = 60.0f;
                info.connected = false;
            }
            info.active = false;
            displays.push_back(info);
        }
        
        return displays;
    }
    
    bool openDisplay(int display_id) override {
        if (fb_fd_ >= 0) {
            closeDisplay();
        }
        
        current_display_id_ = display_id;
        
        // Open framebuffer device
        std::string fb_path = "/dev/fb" + std::to_string(display_id);
        fb_fd_ = open(fb_path.c_str(), O_RDWR);
        if (fb_fd_ < 0) {
            Logger::error("Failed to open framebuffer: " + fb_path);
            return false;
        }
        
        // Get screen info
        if (ioctl(fb_fd_, FBIOGET_VSCREENINFO, &vinfo_) < 0) {
            Logger::error("Failed to get variable screen info");
            close(fb_fd_);
            fb_fd_ = -1;
            return false;
        }
        
        if (ioctl(fb_fd_, FBIOGET_FSCREENINFO, &finfo_) < 0) {
            Logger::error("Failed to get fixed screen info");
            close(fb_fd_);
            fb_fd_ = -1;
            return false;
        }
        
        // Calculate screen size
        screen_size_ = vinfo_.xres * vinfo_.yres * vinfo_.bits_per_pixel / 8;
        
        // Map framebuffer to memory
        fb_ptr_ = (uint8_t*)mmap(0, finfo_.smem_len, 
                                  PROT_READ | PROT_WRITE, 
                                  MAP_SHARED, fb_fd_, 0);
        
        if (fb_ptr_ == MAP_FAILED) {
            Logger::error("Failed to map framebuffer memory");
            close(fb_fd_);
            fb_fd_ = -1;
            return false;
        }
        
        fb_mapped_ = true;
        Logger::info("Opened framebuffer: " + std::to_string(vinfo_.xres) + "x" + 
                    std::to_string(vinfo_.yres) + " @ " + 
                    std::to_string(vinfo_.bits_per_pixel) + "bpp");
        
        return true;
    }
    
    void closeDisplay() override {
        if (fb_mapped_ && fb_ptr_) {
            munmap(fb_ptr_, finfo_.smem_len);
            fb_ptr_ = nullptr;
            fb_mapped_ = false;
        }
        
        if (fb_fd_ >= 0) {
            close(fb_fd_);
            fb_fd_ = -1;
        }
        
        current_display_id_ = -1;
    }
    
    bool isOpen() const override {
        return fb_fd_ >= 0;
    }
    
    DisplayInfo getCurrentDisplay() const override {
        DisplayInfo info;
        info.id = current_display_id_;
        info.connector = "HDMI-" + std::to_string(current_display_id_ + 1);
        
        if (fb_fd_ >= 0) {
            info.width = vinfo_.xres;
            info.height = vinfo_.yres;
            info.refresh_rate = 60.0f;
            info.connected = true;
            info.active = true;
        } else {
            info.width = 1920;
            info.height = 1080;
            info.refresh_rate = 60.0f;
            info.connected = false;
            info.active = false;
        }
        
        return info;
    }
    
    bool displayFrame(const uint8_t* data, int width, int height, 
                     PixelFormat format, int stride) override {
        if (!fb_mapped_ || !fb_ptr_) {
            return false;
        }
        
        // Simple implementation - copy and convert as needed
        // This is not optimized but will work for basic display
        
        int fb_width = vinfo_.xres;
        int fb_height = vinfo_.yres;
        int fb_bpp = vinfo_.bits_per_pixel / 8;
        int fb_stride = finfo_.line_length;
        
        // Clear if sizes don't match (simple letterbox/pillarbox)
        if (width != fb_width || height != fb_height) {
            memset(fb_ptr_, 0, screen_size_);
        }
        
        // Calculate copy dimensions (center the image)
        int copy_width = std::min(width, fb_width);
        int copy_height = std::min(height, fb_height);
        int x_offset = (fb_width - copy_width) / 2;
        int y_offset = (fb_height - copy_height) / 2;
        
        // Copy and convert based on format
        if (format == PixelFormat::BGRA && (fb_bpp == 4 || fb_bpp == 3)) {
            // BGRA to framebuffer format (usually RGB or RGBA)
            for (int y = 0; y < copy_height; y++) {
                const uint8_t* src_row = data + y * stride;
                uint8_t* dst_row = fb_ptr_ + ((y + y_offset) * fb_stride) + (x_offset * fb_bpp);
                
                for (int x = 0; x < copy_width; x++) {
                    const uint8_t* src_pixel = src_row + x * 4;
                    uint8_t* dst_pixel = dst_row + x * fb_bpp;
                    
                    // Convert BGRA to RGB/RGBA
                    dst_pixel[0] = src_pixel[2]; // R
                    dst_pixel[1] = src_pixel[1]; // G
                    dst_pixel[2] = src_pixel[0]; // B
                    if (fb_bpp == 4) {
                        dst_pixel[3] = src_pixel[3]; // A
                    }
                }
            }
        } else if (format == PixelFormat::UYVY && fb_bpp >= 3) {
            // UYVY to RGB conversion (simplified)
            for (int y = 0; y < copy_height; y++) {
                const uint8_t* src_row = data + y * stride;
                uint8_t* dst_row = fb_ptr_ + ((y + y_offset) * fb_stride) + (x_offset * fb_bpp);
                
                for (int x = 0; x < copy_width; x += 2) {
                    // UYVY has 2 pixels in 4 bytes
                    const uint8_t* src = src_row + x * 2;
                    uint8_t y0 = src[1];
                    uint8_t u = src[0];
                    uint8_t y1 = src[3];
                    uint8_t v = src[2];
                    
                    // Simple YUV to RGB conversion for first pixel
                    uint8_t* dst0 = dst_row + x * fb_bpp;
                    int r = y0 + 1.402 * (v - 128);
                    int g = y0 - 0.344 * (u - 128) - 0.714 * (v - 128);
                    int b = y0 + 1.772 * (u - 128);
                    dst0[0] = std::min(255, std::max(0, r));
                    dst0[1] = std::min(255, std::max(0, g));
                    dst0[2] = std::min(255, std::max(0, b));
                    
                    // Second pixel
                    if (x + 1 < copy_width) {
                        uint8_t* dst1 = dst_row + (x + 1) * fb_bpp;
                        r = y1 + 1.402 * (v - 128);
                        g = y1 - 0.344 * (u - 128) - 0.714 * (v - 128);
                        b = y1 + 1.772 * (u - 128);
                        dst1[0] = std::min(255, std::max(0, r));
                        dst1[1] = std::min(255, std::max(0, g));
                        dst1[2] = std::min(255, std::max(0, b));
                    }
                }
            }
        } else {
            // Unsupported format combination
            return false;
        }
        
        // No explicit flush needed for mmap'd framebuffer
        return true;
    }
    
    void clearDisplay() override {
        if (fb_mapped_ && fb_ptr_) {
            memset(fb_ptr_, 0, screen_size_);
        }
    }
    
private:
    int fb_fd_ = -1;
    uint8_t* fb_ptr_ = nullptr;
    bool fb_mapped_ = false;
    size_t screen_size_ = 0;
    
    struct fb_var_screeninfo vinfo_;
    struct fb_fix_screeninfo finfo_;
};

// Factory function
std::unique_ptr<DisplayOutput> createDisplayOutput() {
#ifdef __linux__
    return std::make_unique<FramebufferDisplayOutput>();
#else
    // Windows or other platforms not supported yet
    return nullptr;
#endif
}

} // namespace display
} // namespace ndi_bridge