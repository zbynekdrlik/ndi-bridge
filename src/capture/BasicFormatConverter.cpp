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
        
        // Determine color space based on resolution
        // HD content (720p and above) uses BT.709, SD uses BT.601
        bool useBT709 = (height >= 720);
        
        // Color conversion coefficients
        // BT.601: Kr = 0.299, Kg = 0.587, Kb = 0.114
        // BT.709: Kr = 0.2126, Kg = 0.7152, Kb = 0.0722
        double Kr, Kg, Kb;
        if (useBT709) {
            Kr = 0.2126;
            Kg = 0.7152;
            Kb = 0.0722;
        } else {
            Kr = 0.299;
            Kg = 0.587;
            Kb = 0.114;
        }
        
        // Pre-calculate conversion coefficients
        // For limited range YUV (16-235 for Y, 16-240 for UV)
        double Ky = 255.0 / (235.0 - 16.0);  // 1.164
        double Kuv = 255.0 / (240.0 - 16.0); // 1.138
        
        // Matrix coefficients
        double Kr_scaled = Kr * Kuv;
        double Kg_scaled = Kg * Kuv;
        double Kb_scaled = Kb * Kuv;
        
        // Integer coefficients for performance (scaled by 1024)
        int coef_y = static_cast<int>(Ky * 1024);
        int coef_rv = static_cast<int>((Kuv / (1.0 - Kb)) * 1024);
        int coef_gu = static_cast<int>((Kb_scaled * 2.0 / Kg) * 1024);
        int coef_gv = static_cast<int>((Kr_scaled * 2.0 / Kg) * 1024);
        int coef_bu = static_cast<int>((Kuv / (1.0 - Kr)) * 1024);
        
        for (int y = 0; y < height; y++) {
            const uint8_t* srcRow = src + y * srcStride;
            uint8_t* dstRow = dst + y * dstStride;
            
            for (int x = 0; x < width; x += 2) {
                // UYVY format: U0 Y0 V0 Y1
                int u = srcRow[0];
                int y0 = srcRow[1];
                int v = srcRow[2];
                int y1 = srcRow[3];
                
                // Check if we have full range or limited range
                // Full range uses 0-255, limited uses 16-235/240
                // Auto-detect based on Y values (if we see values < 16 or > 235, assume full range)
                bool isFullRange = (y0 < 16 || y0 > 235 || y1 < 16 || y1 > 235);
                
                if (!isFullRange) {
                    // Limited range conversion
                    y0 = ((y0 - 16) * coef_y + 512) >> 10;
                    y1 = ((y1 - 16) * coef_y + 512) >> 10;
                    u = u - 128;
                    v = v - 128;
                } else {
                    // Full range - no offset needed
                    u = u - 128;
                    v = v - 128;
                }
                
                // YUV to RGB conversion using proper coefficients
                int r0, g0, b0, r1, g1, b1;
                
                if (!isFullRange) {
                    // Limited range with proper coefficients
                    r0 = y0 + ((v * coef_rv + 512) >> 10);
                    g0 = y0 - ((u * coef_gu + v * coef_gv + 512) >> 10);
                    b0 = y0 + ((u * coef_bu + 512) >> 10);
                    
                    r1 = y1 + ((v * coef_rv + 512) >> 10);
                    g1 = y1 - ((u * coef_gu + v * coef_gv + 512) >> 10);
                    b1 = y1 + ((u * coef_bu + 512) >> 10);
                } else {
                    // Full range conversion
                    if (useBT709) {
                        // BT.709 full range
                        r0 = y0 + ((v * 1575 + 512) >> 10);
                        g0 = y0 - ((u * 187 + v * 468 + 512) >> 10);
                        b0 = y0 + ((u * 1856 + 512) >> 10);
                        
                        r1 = y1 + ((v * 1575 + 512) >> 10);
                        g1 = y1 - ((u * 187 + v * 468 + 512) >> 10);
                        b1 = y1 + ((u * 1856 + 512) >> 10);
                    } else {
                        // BT.601 full range
                        r0 = y0 + ((v * 1402 + 512) >> 10);
                        g0 = y0 - ((u * 344 + v * 714 + 512) >> 10);
                        b0 = y0 + ((u * 1772 + 512) >> 10);
                        
                        r1 = y1 + ((v * 1402 + 512) >> 10);
                        g1 = y1 - ((u * 344 + v * 714 + 512) >> 10);
                        b1 = y1 + ((u * 1772 + 512) >> 10);
                    }
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
                int u = uRow[x / 2] - 128;
                int v = vRow[x / 2] - 128;
                
                // Check for full range
                bool isFullRange = (yVal < 16 || yVal > 235);
                
                int r, g, b;
                if (!isFullRange) {
                    // Limited range
                    yVal = ((yVal - 16) * 1164 + 512) >> 10;
                    
                    if (useBT709) {
                        r = yVal + ((v * 1793 + 512) >> 10);
                        g = yVal - ((u * 213 + v * 533 + 512) >> 10);
                        b = yVal + ((u * 2049 + 512) >> 10);
                    } else {
                        r = yVal + ((v * 1596 + 512) >> 10);
                        g = yVal - ((u * 391 + v * 813 + 512) >> 10);
                        b = yVal + ((u * 2018 + 512) >> 10);
                    }
                } else {
                    // Full range
                    if (useBT709) {
                        r = yVal + ((v * 1575 + 512) >> 10);
                        g = yVal - ((u * 187 + v * 468 + 512) >> 10);
                        b = yVal + ((u * 1856 + 512) >> 10);
                    } else {
                        r = yVal + ((v * 1402 + 512) >> 10);
                        g = yVal - ((u * 344 + v * 714 + 512) >> 10);
                        b = yVal + ((u * 1772 + 512) >> 10);
                    }
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
                int u = uvRow[uvIndex] - 128;
                int v = uvRow[uvIndex + 1] - 128;
                
                // Check for full range
                bool isFullRange = (yVal < 16 || yVal > 235);
                
                int r, g, b;
                if (!isFullRange) {
                    // Limited range
                    yVal = ((yVal - 16) * 1164 + 512) >> 10;
                    
                    if (useBT709) {
                        r = yVal + ((v * 1793 + 512) >> 10);
                        g = yVal - ((u * 213 + v * 533 + 512) >> 10);
                        b = yVal + ((u * 2049 + 512) >> 10);
                    } else {
                        r = yVal + ((v * 1596 + 512) >> 10);
                        g = yVal - ((u * 391 + v * 813 + 512) >> 10);
                        b = yVal + ((u * 2018 + 512) >> 10);
                    }
                } else {
                    // Full range
                    if (useBT709) {
                        r = yVal + ((v * 1575 + 512) >> 10);
                        g = yVal - ((u * 187 + v * 468 + 512) >> 10);
                        b = yVal + ((u * 1856 + 512) >> 10);
                    } else {
                        r = yVal + ((v * 1402 + 512) >> 10);
                        g = yVal - ((u * 344 + v * 714 + 512) >> 10);
                        b = yVal + ((u * 1772 + 512) >> 10);
                    }
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
