// BasicFormatConverter.cpp
#include "FormatConverterFactory.h"
#include <algorithm>
#include <cstring>

// Basic software format converter implementation
class BasicFormatConverter : public IFormatConverter {
public:
    bool ConvertUYVYToBGRA(const uint8_t* src, uint8_t* dst, 
                          int width, int height, int srcStride) override {
        if (!src || !dst || width <= 0 || height <= 0) {
            return false;
        }
        
        const int dstStride = width * 4;
        
        for (int y = 0; y < height; y++) {
            const uint8_t* srcRow = src + y * srcStride;
            uint8_t* dstRow = dst + y * dstStride;
            
            for (int x = 0; x < width; x += 2) {
                // UYVY format: U0 Y0 V0 Y1
                int u = srcRow[0] - 128;
                int y0 = srcRow[1] - 16;
                int v = srcRow[2] - 128;
                int y1 = srcRow[3] - 16;
                
                // YUV to RGB conversion (ITU-R BT.601)
                int c0 = y0 * 298;
                int c1 = y1 * 298;
                int d = u * 100;
                int e = v * 208;
                int uv = u * 516 + v * 409;
                
                // First pixel
                int r0 = (c0 + e + 128) >> 8;
                int g0 = (c0 - d - uv + 128) >> 8;
                int b0 = (c0 + d + 128) >> 8;
                
                // Second pixel
                int r1 = (c1 + e + 128) >> 8;
                int g1 = (c1 - d - uv + 128) >> 8;
                int b1 = (c1 + d + 128) >> 8;
                
                // Clamp and write BGRA
                dstRow[0] = std::max(0, std::min(255, b0));  // B
                dstRow[1] = std::max(0, std::min(255, g0));  // G
                dstRow[2] = std::max(0, std::min(255, r0));  // R
                dstRow[3] = 255;                              // A
                
                dstRow[4] = std::max(0, std::min(255, b1));  // B
                dstRow[5] = std::max(0, std::min(255, g1));  // G
                dstRow[6] = std::max(0, std::min(255, r1));  // R
                dstRow[7] = 255;                              // A
                
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
        
        for (int y = 0; y < height; y++) {
            const uint8_t* yRow = srcY + y * strideY;
            const uint8_t* uRow = srcU + (y / 2) * strideU;
            const uint8_t* vRow = srcV + (y / 2) * strideV;
            uint8_t* dstRow = dst + y * dstStride;
            
            for (int x = 0; x < width; x++) {
                int yVal = yRow[x] - 16;
                int u = uRow[x / 2] - 128;
                int v = vRow[x / 2] - 128;
                
                int c = yVal * 298;
                int d = u * 100;
                int e = v * 208;
                int uv = u * 516 + v * 409;
                
                int r = (c + e + 128) >> 8;
                int g = (c - d - uv + 128) >> 8;
                int b = (c + d + 128) >> 8;
                
                dstRow[x * 4 + 0] = std::max(0, std::min(255, b));
                dstRow[x * 4 + 1] = std::max(0, std::min(255, g));
                dstRow[x * 4 + 2] = std::max(0, std::min(255, r));
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
        
        for (int y = 0; y < height; y++) {
            const uint8_t* yRow = srcY + y * strideY;
            const uint8_t* uvRow = srcUV + (y / 2) * strideUV;
            uint8_t* dstRow = dst + y * dstStride;
            
            for (int x = 0; x < width; x++) {
                int yVal = yRow[x] - 16;
                int uvIndex = (x / 2) * 2;
                int u = uvRow[uvIndex] - 128;
                int v = uvRow[uvIndex + 1] - 128;
                
                int c = yVal * 298;
                int d = u * 100;
                int e = v * 208;
                int uv = u * 516 + v * 409;
                
                int r = (c + e + 128) >> 8;
                int g = (c - d - uv + 128) >> 8;
                int b = (c + d + 128) >> 8;
                
                dstRow[x * 4 + 0] = std::max(0, std::min(255, b));
                dstRow[x * 4 + 1] = std::max(0, std::min(255, g));
                dstRow[x * 4 + 2] = std::max(0, std::min(255, r));
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
