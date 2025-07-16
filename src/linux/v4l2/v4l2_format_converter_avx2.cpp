// v4l2_format_converter_avx2.cpp
#include "v4l2_format_converter_avx2.h"
#include "../../common/logger.h"
#include <cpuid.h>
#include <cstring>

namespace ndi_bridge {
namespace v4l2 {

// Initialize AVX2 constants
// FIXED: Scale coefficients by 256 for use with mulhi_epi16
const __m256i V4L2FormatConverterAVX2::Y_OFFSET = _mm256_set1_epi16(16);
const __m256i V4L2FormatConverterAVX2::UV_OFFSET = _mm256_set1_epi16(128);
const __m256i V4L2FormatConverterAVX2::Y_COEFF = _mm256_set1_epi16(298 * 256);  // Scaled by 256
const __m256i V4L2FormatConverterAVX2::U_BLUE_COEFF = _mm256_set1_epi16(516 * 256);  // Scaled by 256
const __m256i V4L2FormatConverterAVX2::U_GREEN_COEFF = _mm256_set1_epi16(-100 * 256);  // Scaled by 256
const __m256i V4L2FormatConverterAVX2::V_RED_COEFF = _mm256_set1_epi16(409 * 256);  // Scaled by 256
const __m256i V4L2FormatConverterAVX2::V_GREEN_COEFF = _mm256_set1_epi16(-208 * 256);  // Scaled by 256
const __m256i V4L2FormatConverterAVX2::ROUND_OFFSET = _mm256_set1_epi16(128 * 256);  // Scaled by 256
const __m256i V4L2FormatConverterAVX2::ALPHA_VALUE = _mm256_set1_epi8(static_cast<char>(0xFF));

// Shuffle masks for YUYV extraction (32 bytes -> 16 Y, 8 U, 8 V)
const __m256i V4L2FormatConverterAVX2::YUYV_Y_SHUFFLE = _mm256_setr_epi8(
    0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30,
    0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30
);

const __m256i V4L2FormatConverterAVX2::YUYV_U_SHUFFLE = _mm256_setr_epi8(
    1, 1, 5, 5, 9, 9, 13, 13, 17, 17, 21, 21, 25, 25, 29, 29,
    1, 1, 5, 5, 9, 9, 13, 13, 17, 17, 21, 21, 25, 25, 29, 29
);

const __m256i V4L2FormatConverterAVX2::YUYV_V_SHUFFLE = _mm256_setr_epi8(
    3, 3, 7, 7, 11, 11, 15, 15, 19, 19, 23, 23, 27, 27, 31, 31,
    3, 3, 7, 7, 11, 11, 15, 15, 19, 19, 23, 23, 27, 27, 31, 31
);

// Shuffle masks for UYVY extraction
const __m256i V4L2FormatConverterAVX2::UYVY_Y_SHUFFLE = _mm256_setr_epi8(
    1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31,
    1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31
);

const __m256i V4L2FormatConverterAVX2::UYVY_U_SHUFFLE = _mm256_setr_epi8(
    0, 0, 4, 4, 8, 8, 12, 12, 16, 16, 20, 20, 24, 24, 28, 28,
    0, 0, 4, 4, 8, 8, 12, 12, 16, 16, 20, 20, 24, 24, 28, 28
);

const __m256i V4L2FormatConverterAVX2::UYVY_V_SHUFFLE = _mm256_setr_epi8(
    2, 2, 6, 6, 10, 10, 14, 14, 18, 18, 22, 22, 26, 26, 30, 30,
    2, 2, 6, 6, 10, 10, 14, 14, 18, 18, 22, 22, 26, 26, 30, 30
);

bool V4L2FormatConverterAVX2::isAVX2Available() {
    unsigned int eax, ebx, ecx, edx;
    
    // Check for AVX2 support
    if (__get_cpuid_max(0, nullptr) >= 7) {
        __cpuid_count(7, 0, eax, ebx, ecx, edx);
        return (ebx & (1 << 5)) != 0; // AVX2 bit
    }
    
    return false;
}

bool V4L2FormatConverterAVX2::convertYUYVtoBGRA_AVX2(const uint8_t* input, int width, int height,
                                                      uint8_t* output) {
    // Process 16 pixels at a time
    const int pixels_per_iteration = 16;
    const int aligned_width = (width / pixels_per_iteration) * pixels_per_iteration;
    
    for (int y = 0; y < height; y++) {
        const uint8_t* src_row = input + y * width * 2;
        uint8_t* dst_row = output + y * width * 4;
        
        // Process aligned portion with AVX2
        for (int x = 0; x < aligned_width; x += pixels_per_iteration) {
            // Load 32 bytes (16 YUYV pixels)
            __m256i yuyv = _mm256_loadu_si256((const __m256i*)(src_row + x * 2));
            
            // Extract Y, U, V components
            __m256i y_vec = _mm256_shuffle_epi8(yuyv, YUYV_Y_SHUFFLE);
            __m256i u_vec = _mm256_shuffle_epi8(yuyv, YUYV_U_SHUFFLE);
            __m256i v_vec = _mm256_shuffle_epi8(yuyv, YUYV_V_SHUFFLE);
            
            // Convert to BGRA
            processYUV16_AVX2(y_vec, u_vec, v_vec, dst_row + x * 4);
        }
        
        // Handle remaining pixels with scalar code
        for (int x = aligned_width; x < width; x += 2) {
            uint8_t y0 = src_row[x * 2 + 0];
            uint8_t u  = src_row[x * 2 + 1];
            uint8_t y1 = src_row[x * 2 + 2];
            uint8_t v  = src_row[x * 2 + 3];
            
            // ITU-R BT.601 conversion
            int c0 = y0 - 16;
            int c1 = y1 - 16;
            int d = u - 128;
            int e = v - 128;
            
            // Calculate RGB for pixel 0
            int r0 = (298 * c0 + 409 * e + 128) >> 8;
            int g0 = (298 * c0 - 100 * d - 208 * e + 128) >> 8;
            int b0 = (298 * c0 + 516 * d + 128) >> 8;
            
            // Calculate RGB for pixel 1
            int r1 = (298 * c1 + 409 * e + 128) >> 8;
            int g1 = (298 * c1 - 100 * d - 208 * e + 128) >> 8;
            int b1 = (298 * c1 + 516 * d + 128) >> 8;
            
            // Clamp and write BGRA
            dst_row[x * 4 + 0] = (b0 < 0) ? 0 : (b0 > 255) ? 255 : b0;
            dst_row[x * 4 + 1] = (g0 < 0) ? 0 : (g0 > 255) ? 255 : g0;
            dst_row[x * 4 + 2] = (r0 < 0) ? 0 : (r0 > 255) ? 255 : r0;
            dst_row[x * 4 + 3] = 255;
            
            if (x + 1 < width) {
                dst_row[x * 4 + 4] = (b1 < 0) ? 0 : (b1 > 255) ? 255 : b1;
                dst_row[x * 4 + 5] = (g1 < 0) ? 0 : (g1 > 255) ? 255 : g1;
                dst_row[x * 4 + 6] = (r1 < 0) ? 0 : (r1 > 255) ? 255 : r1;
                dst_row[x * 4 + 7] = 255;
            }
        }
    }
    
    return true;
}

bool V4L2FormatConverterAVX2::convertUYVYtoBGRA_AVX2(const uint8_t* input, int width, int height,
                                                      uint8_t* output) {
    const int pixels_per_iteration = 16;
    const int aligned_width = (width / pixels_per_iteration) * pixels_per_iteration;
    
    for (int y = 0; y < height; y++) {
        const uint8_t* src_row = input + y * width * 2;
        uint8_t* dst_row = output + y * width * 4;
        
        // Process aligned portion with AVX2
        for (int x = 0; x < aligned_width; x += pixels_per_iteration) {
            // Load 32 bytes (16 UYVY pixels)
            __m256i uyvy = _mm256_loadu_si256((const __m256i*)(src_row + x * 2));
            
            // Extract Y, U, V components
            __m256i y_vec = _mm256_shuffle_epi8(uyvy, UYVY_Y_SHUFFLE);
            __m256i u_vec = _mm256_shuffle_epi8(uyvy, UYVY_U_SHUFFLE);
            __m256i v_vec = _mm256_shuffle_epi8(uyvy, UYVY_V_SHUFFLE);
            
            // Convert to BGRA
            processYUV16_AVX2(y_vec, u_vec, v_vec, dst_row + x * 4);
        }
        
        // Handle remaining pixels
        for (int x = aligned_width; x < width; x += 2) {
            uint8_t u  = src_row[x * 2 + 0];
            uint8_t y0 = src_row[x * 2 + 1];
            uint8_t v  = src_row[x * 2 + 2];
            uint8_t y1 = src_row[x * 2 + 3];
            
            int c0 = y0 - 16;
            int c1 = y1 - 16;
            int d = u - 128;
            int e = v - 128;
            
            int r0 = (298 * c0 + 409 * e + 128) >> 8;
            int g0 = (298 * c0 - 100 * d - 208 * e + 128) >> 8;
            int b0 = (298 * c0 + 516 * d + 128) >> 8;
            
            int r1 = (298 * c1 + 409 * e + 128) >> 8;
            int g1 = (298 * c1 - 100 * d - 208 * e + 128) >> 8;
            int b1 = (298 * c1 + 516 * d + 128) >> 8;
            
            dst_row[x * 4 + 0] = (b0 < 0) ? 0 : (b0 > 255) ? 255 : b0;
            dst_row[x * 4 + 1] = (g0 < 0) ? 0 : (g0 > 255) ? 255 : g0;
            dst_row[x * 4 + 2] = (r0 < 0) ? 0 : (r0 > 255) ? 255 : r0;
            dst_row[x * 4 + 3] = 255;
            
            if (x + 1 < width) {
                dst_row[x * 4 + 4] = (b1 < 0) ? 0 : (b1 > 255) ? 255 : b1;
                dst_row[x * 4 + 5] = (g1 < 0) ? 0 : (g1 > 255) ? 255 : g1;
                dst_row[x * 4 + 6] = (r1 < 0) ? 0 : (r1 > 255) ? 255 : r1;
                dst_row[x * 4 + 7] = 255;
            }
        }
    }
    
    return true;
}

bool V4L2FormatConverterAVX2::convertNV12toBGRA_AVX2(const uint8_t* input, int width, int height,
                                                      uint8_t* output) {
    const uint8_t* y_plane = input;
    const uint8_t* uv_plane = input + width * height;
    
    // Process 16 pixels at a time
    const int pixels_per_iteration = 16;
    const int aligned_width = (width / pixels_per_iteration) * pixels_per_iteration;
    
    // Shuffle mask to separate and duplicate UV values for 2x2 blocks
    // From UVUVUVUV... to UUUUUUUU... and VVVVVVVV...
    const __m256i uv_shuf_u = _mm256_setr_epi8(
        0, 0, 2, 2, 4, 4, 6, 6, 8, 8, 10, 10, 12, 12, 14, 14,
        16, 16, 18, 18, 20, 20, 22, 22, 24, 24, 26, 26, 28, 28, 30, 30
    );
    const __m256i uv_shuf_v = _mm256_setr_epi8(
        1, 1, 3, 3, 5, 5, 7, 7, 9, 9, 11, 11, 13, 13, 15, 15,
        17, 17, 19, 19, 21, 21, 23, 23, 25, 25, 27, 27, 29, 29, 31, 31
    );
    
    for (int y = 0; y < height; y += 2) {
        // Process two Y rows at a time (since UV is subsampled)
        const uint8_t* y_row0 = y_plane + y * width;
        const uint8_t* y_row1 = (y + 1 < height) ? y_plane + (y + 1) * width : y_row0;
        const uint8_t* uv_row = uv_plane + (y / 2) * width;
        uint8_t* dst_row0 = output + y * width * 4;
        uint8_t* dst_row1 = output + (y + 1) * width * 4;
        
        for (int x = 0; x < aligned_width; x += pixels_per_iteration) {
            // Load 16 Y values for each row
            __m128i y0_128 = _mm_loadu_si128((const __m128i*)(y_row0 + x));
            __m128i y1_128 = _mm_loadu_si128((const __m128i*)(y_row1 + x));
            
            // Load as 256-bit and keep as 8-bit
            __m256i y0_256 = _mm256_set_m128i(_mm_setzero_si128(), y0_128);
            __m256i y1_256 = _mm256_set_m128i(_mm_setzero_si128(), y1_128);
            
            // Load 16 bytes of interleaved UV (8 U/V pairs)
            __m128i uv_128 = _mm_loadu_si128((const __m128i*)(uv_row + x));
            
            // Duplicate UV data to fill 256-bit register
            __m256i uv_256 = _mm256_set_m128i(uv_128, uv_128);
            
            // Separate and duplicate U and V values
            __m256i u_vec = _mm256_shuffle_epi8(uv_256, uv_shuf_u);
            __m256i v_vec = _mm256_shuffle_epi8(uv_256, uv_shuf_v);
            
            // Process both rows with the correct Y vectors
            processYUV16_AVX2(y0_256, u_vec, v_vec, dst_row0 + x * 4);
            if (y + 1 < height) {
                processYUV16_AVX2(y1_256, u_vec, v_vec, dst_row1 + x * 4);
            }
        }
        
        // Handle remaining pixels with scalar code
        for (int x = aligned_width; x < width; x++) {
            uint8_t y0_val = y_row0[x];
            uint8_t y1_val = (y + 1 < height) ? y_row1[x] : y0_val;
            uint8_t u = uv_row[(x / 2) * 2];
            uint8_t v = uv_row[(x / 2) * 2 + 1];
            
            int c0 = y0_val - 16;
            int c1 = y1_val - 16;
            int d = u - 128;
            int e = v - 128;
            
            int r0 = (298 * c0 + 409 * e + 128) >> 8;
            int g0 = (298 * c0 - 100 * d - 208 * e + 128) >> 8;
            int b0 = (298 * c0 + 516 * d + 128) >> 8;
            
            int r1 = (298 * c1 + 409 * e + 128) >> 8;
            int g1 = (298 * c1 - 100 * d - 208 * e + 128) >> 8;
            int b1 = (298 * c1 + 516 * d + 128) >> 8;
            
            dst_row0[x * 4 + 0] = (b0 < 0) ? 0 : (b0 > 255) ? 255 : b0;
            dst_row0[x * 4 + 1] = (g0 < 0) ? 0 : (g0 > 255) ? 255 : g0;
            dst_row0[x * 4 + 2] = (r0 < 0) ? 0 : (r0 > 255) ? 255 : r0;
            dst_row0[x * 4 + 3] = 255;
            
            if (y + 1 < height) {
                dst_row1[x * 4 + 0] = (b1 < 0) ? 0 : (b1 > 255) ? 255 : b1;
                dst_row1[x * 4 + 1] = (g1 < 0) ? 0 : (g1 > 255) ? 255 : g1;
                dst_row1[x * 4 + 2] = (r1 < 0) ? 0 : (r1 > 255) ? 255 : r1;
                dst_row1[x * 4 + 3] = 255;
            }
        }
    }
    
    return true;
}

} // namespace v4l2
} // namespace ndi_bridge
