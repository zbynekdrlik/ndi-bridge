// BasicFormatConverter.cpp
#include "FormatConverterFactory.h"
#include <algorithm>
#include <cstring>

// Basic software format converter implementation
class BasicFormatConverter : public IFormatConverter {
public:
    bool ConvertUYVYToBGRA(const uint8_t* src, uint8_t* dst, 
                          int width, int height, int srcStride) override {
        // Use auto-detection for backward compatibility
        ColorSpaceInfo autoInfo;
        autoInfo.space = ColorSpaceInfo::CS_AUTO;
        autoInfo.range = ColorSpaceInfo::CR_AUTO;
        return ConvertUYVYToBGRA(src, dst, width, height, srcStride, autoInfo);
    }
    
    bool ConvertUYVYToBGRA(const uint8_t* src, uint8_t* dst, 
                          int width, int height, int srcStride,
                          const ColorSpaceInfo& info) override {
        if (!src || !dst || width <= 0 || height <= 0) {
            return false;
        }
        
        const int dstStride = width * 4;
        
        // Determine color space
        bool useBT709;
        if (info.space == ColorSpaceInfo::CS_BT709) {
            useBT709 = true;
        } else if (info.space == ColorSpaceInfo::CS_BT601) {
            useBT709 = false;
        } else {
            // Auto-detect based on resolution
            useBT709 = (height >= 720);
        }
        
        // Determine color range
        bool useFullRange;
        if (info.range == ColorSpaceInfo::CR_FULL) {
            useFullRange = true;
        } else if (info.range == ColorSpaceInfo::CR_LIMITED) {
            useFullRange = false;
        } else {
            // Default to limited range for broadcast content
            useFullRange = false;
        }
        
        for (int y = 0; y < height; y++) {
            const uint8_t* srcRow = src + y * srcStride;
            uint8_t* dstRow = dst + y * dstStride;
            
            for (int x = 0; x < width; x += 2) {
                // UYVY format: U0 Y0 V0 Y1
                int u = srcRow[0];
                int y0 = srcRow[1];
                int v = srcRow[2];
                int y1 = srcRow[3];
                
                if (!useFullRange) {
                    // Convert from limited range YUV to RGB
                    // Y: [16,235] -> [0,255]
                    // UV: [16,240] -> [-112,112]
                    y0 = ((y0 - 16) * 255) / 219;
                    y1 = ((y1 - 16) * 255) / 219;
                    u = ((u - 128) * 255) / 224;
                    v = ((v - 128) * 255) / 224;
                    
                    // Clamp Y values
                    y0 = std::max(0, std::min(255, y0));
                    y1 = std::max(0, std::min(255, y1));
                } else {
                    // Full range - just center UV
                    u = u - 128;
                    v = v - 128;
                }
                
                // YUV to RGB conversion
                int r0, g0, b0, r1, g1, b1;
                
                if (useBT709) {
                    // BT.709 coefficients
                    // R = Y + 1.5748 * V
                    // G = Y - 0.1873 * U - 0.4681 * V
                    // B = Y + 1.8556 * U
                    r0 = y0 + ((1575 * v + 500) / 1000);
                    g0 = y0 - ((187 * u + 468 * v + 500) / 1000);
                    b0 = y0 + ((1856 * u + 500) / 1000);
                    
                    r1 = y1 + ((1575 * v + 500) / 1000);
                    g1 = y1 - ((187 * u + 468 * v + 500) / 1000);
                    b1 = y1 + ((1856 * u + 500) / 1000);
                } else {
                    // BT.601 coefficients
                    // R = Y + 1.402 * V
                    // G = Y - 0.344 * U - 0.714 * V
                    // B = Y + 1.772 * U
                    r0 = y0 + ((1402 * v + 500) / 1000);
                    g0 = y0 - ((344 * u + 714 * v + 500) / 1000);
                    b0 = y0 + ((1772 * u + 500) / 1000);
                    
                    r1 = y1 + ((1402 * v + 500) / 1000);
                    g1 = y1 - ((344 * u + 714 * v + 500) / 1000);
                    b1 = y1 + ((1772 * u + 500) / 1000);
                }
                
                // Clamp and write BGRA
                dstRow[0] = static_cast<uint8_t>(std::max(0, std::min(255, b0)));  // B
                dstRow[1] = static_cast<uint8_t>(std::max(0, std::min(255, g0)));  // G
                dstRow[2] = static_cast<uint8_t>(std::max(0, std::min(255, r0)));  // R
                dstRow[3] = 255;                                                    // A
                
                dstRow[4] = static_cast<uint8_t>(std::max(0, std::min(255, b1)));  // B
                dstRow[5] = static_cast<uint8_t>(std::max(0, std::min(255, g1)));  // G
                dstRow[6] = static_cast<uint8_t>(std::max(0, std::min(255, r1)));  // R
                dstRow[7] = 255;                                                    // A
                
                srcRow += 4;
                dstRow += 8;
            }
        }
        
        return true;
    }
    
    bool ConvertYUV420ToBGRA(const uint8_t* srcY, const uint8_t* srcU, const uint8_t* srcV,
                            uint8_t* dst, int width, int height, 
                            int strideY, int strideU, int strideV) override {
        if (!srcY || !srcU || !srcV || !dst || width <= 0 || height <= 0) {
            return false;
        }
        
        const int dstStride = width * 4;
        
        // Determine color space based on resolution
        bool useBT709 = (height >= 720);
        
        for (int y = 0; y < height; y++) {
            const uint8_t* yRow = srcY + y * strideY;
            const uint8_t* uRow = srcU + (y / 2) * strideU;
            const uint8_t* vRow = srcV + (y / 2) * strideV;
            uint8_t* dstRow = dst + y * dstStride;
            
            for (int x = 0; x < width; x++) {
                int yVal = yRow[x];
                int u = uRow[x / 2];
                int v = vRow[x / 2];
                
                // Convert from limited range
                yVal = ((yVal - 16) * 255) / 219;
                u = ((u - 128) * 255) / 224;
                v = ((v - 128) * 255) / 224;
                
                yVal = std::max(0, std::min(255, yVal));
                
                int r, g, b;
                if (useBT709) {
                    r = yVal + ((1575 * v + 500) / 1000);
                    g = yVal - ((187 * u + 468 * v + 500) / 1000);
                    b = yVal + ((1856 * u + 500) / 1000);
                } else {
                    r = yVal + ((1402 * v + 500) / 1000);
                    g = yVal - ((344 * u + 714 * v + 500) / 1000);
                    b = yVal + ((1772 * u + 500) / 1000);
                }
                
                dstRow[x * 4 + 0] = static_cast<uint8_t>(std::max(0, std::min(255, b)));
                dstRow[x * 4 + 1] = static_cast<uint8_t>(std::max(0, std::min(255, g)));
                dstRow[x * 4 + 2] = static_cast<uint8_t>(std::max(0, std::min(255, r)));
                dstRow[x * 4 + 3] = 255;
            }
        }
        
        return true;
    }
    
    bool ConvertNV12ToBGRA(const uint8_t* srcY, const uint8_t* srcUV,
                          uint8_t* dst, int width, int height,
                          int strideY, int strideUV) override {
        if (!srcY || !srcUV || !dst || width <= 0 || height <= 0) {
            return false;
        }
        
        const int dstStride = width * 4;
        
        // Determine color space based on resolution
        bool useBT709 = (height >= 720);
        
        for (int y = 0; y < height; y++) {
            const uint8_t* yRow = srcY + y * strideY;
            const uint8_t* uvRow = srcUV + (y / 2) * strideUV;
            uint8_t* dstRow = dst + y * dstStride;
            
            for (int x = 0; x < width; x++) {
                int yVal = yRow[x];
                int uvIndex = (x / 2) * 2;
                int u = uvRow[uvIndex];
                int v = uvRow[uvIndex + 1];
                
                // Convert from limited range
                yVal = ((yVal - 16) * 255) / 219;
                u = ((u - 128) * 255) / 224;
                v = ((v - 128) * 255) / 224;
                
                yVal = std::max(0, std::min(255, yVal));
                
                int r, g, b;
                if (useBT709) {
                    r = yVal + ((1575 * v + 500) / 1000);
                    g = yVal - ((187 * u + 468 * v + 500) / 1000);
                    b = yVal + ((1856 * u + 500) / 1000);
                } else {
                    r = yVal + ((1402 * v + 500) / 1000);
                    g = yVal - ((344 * u + 714 * v + 500) / 1000);
                    b = yVal + ((1772 * u + 500) / 1000);
                }
                
                dstRow[x * 4 + 0] = static_cast<uint8_t>(std::max(0, std::min(255, b)));
                dstRow[x * 4 + 1] = static_cast<uint8_t>(std::max(0, std::min(255, g)));
                dstRow[x * 4 + 2] = static_cast<uint8_t>(std::max(0, std::min(255, r)));
                dstRow[x * 4 + 3] = 255;
            }
        }
        
        return true;
    }
    
    bool ConvertRGB24ToBGRA(const uint8_t* src, uint8_t* dst,
                           int width, int height, int srcStride) override {
        if (!src || !dst || width <= 0 || height <= 0) {
            return false;
        }
        
        const int dstStride = width * 4;
        
        for (int y = 0; y < height; y++) {
            const uint8_t* srcRow = src + y * srcStride;
            uint8_t* dstRow = dst + y * dstStride;
            
            for (int x = 0; x < width; x++) {
                dstRow[x * 4 + 0] = srcRow[x * 3 + 2]; // B
                dstRow[x * 4 + 1] = srcRow[x * 3 + 1]; // G
                dstRow[x * 4 + 2] = srcRow[x * 3 + 0]; // R
                dstRow[x * 4 + 3] = 255;                // A
            }
        }
        
        return true;
    }
};

// Factory implementation
std::unique_ptr<IFormatConverter> FormatConverterFactory::Create() {
    return std::make_unique<BasicFormatConverter>();
}
