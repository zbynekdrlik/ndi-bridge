// v4l2_format_converter_avx2.h
#pragma once

#include <immintrin.h>
#include <cstdint>

namespace ndi_bridge {
namespace v4l2 {

/**
 * @brief AVX2 optimized YUV to RGB conversion
 * 
 * Optimized for Intel N100 processor with AVX2 support.
 * Processes 16 pixels at a time for maximum throughput.
 * 
 * Version: 1.3.1
 */
class V4L2FormatConverterAVX2 {
public:
    // Check if AVX2 is available at runtime
    static bool isAVX2Available();
    
    // Optimized YUYV to BGRA conversion (16 pixels at a time)
    static bool convertYUYVtoBGRA_AVX2(const uint8_t* input, int width, int height,
                                        uint8_t* output);
    
    // Optimized UYVY to BGRA conversion (16 pixels at a time)
    static bool convertUYVYtoBGRA_AVX2(const uint8_t* input, int width, int height,
                                        uint8_t* output);
    
    // Optimized NV12 to BGRA conversion
    static bool convertNV12toBGRA_AVX2(const uint8_t* input, int width, int height,
                                        uint8_t* output);
    
private:
    // AVX2 constants for YUV to RGB conversion (ITU-R BT.601)
    static const __m256i Y_OFFSET;      // 16
    static const __m256i UV_OFFSET;     // 128
    static const __m256i Y_COEFF;       // 298
    static const __m256i U_BLUE_COEFF;  // 516
    static const __m256i U_GREEN_COEFF; // -100
    static const __m256i V_RED_COEFF;   // 409
    static const __m256i V_GREEN_COEFF; // -208
    static const __m256i ROUND_OFFSET;  // 128
    static const __m256i ALPHA_VALUE;   // 255
    
    // Helper to process 16 YUV pixels to BGRA using AVX2
    static inline void processYUV16_AVX2(
        const __m256i& y_vec,      // 16 Y values
        const __m256i& u_vec,      // 16 U values (duplicated for 4:2:2)
        const __m256i& v_vec,      // 16 V values (duplicated for 4:2:2)
        uint8_t* output            // Output 64 bytes (16 BGRA pixels)
    );
    
    // Shuffle masks for format conversion
    static const __m256i YUYV_Y_SHUFFLE;
    static const __m256i YUYV_U_SHUFFLE;
    static const __m256i YUYV_V_SHUFFLE;
    static const __m256i UYVY_Y_SHUFFLE;
    static const __m256i UYVY_U_SHUFFLE;
    static const __m256i UYVY_V_SHUFFLE;
};

// Inline implementation for maximum performance
inline void V4L2FormatConverterAVX2::processYUV16_AVX2(
    const __m256i& y_vec,
    const __m256i& u_vec,
    const __m256i& v_vec,
    uint8_t* output)
{
    // Convert to 16-bit for calculations
    __m256i y_lo = _mm256_unpacklo_epi8(y_vec, _mm256_setzero_si256());
    __m256i y_hi = _mm256_unpackhi_epi8(y_vec, _mm256_setzero_si256());
    __m256i u_lo = _mm256_unpacklo_epi8(u_vec, _mm256_setzero_si256());
    __m256i u_hi = _mm256_unpackhi_epi8(u_vec, _mm256_setzero_si256());
    __m256i v_lo = _mm256_unpacklo_epi8(v_vec, _mm256_setzero_si256());
    __m256i v_hi = _mm256_unpackhi_epi8(v_vec, _mm256_setzero_si256());
    
    // Apply offsets
    y_lo = _mm256_sub_epi16(y_lo, Y_OFFSET);
    y_hi = _mm256_sub_epi16(y_hi, Y_OFFSET);
    u_lo = _mm256_sub_epi16(u_lo, UV_OFFSET);
    u_hi = _mm256_sub_epi16(u_hi, UV_OFFSET);
    v_lo = _mm256_sub_epi16(v_lo, UV_OFFSET);
    v_hi = _mm256_sub_epi16(v_hi, UV_OFFSET);
    
    // Calculate RGB components (low 8 pixels)
    __m256i r_lo = _mm256_add_epi16(
        _mm256_mulhi_epi16(y_lo, Y_COEFF),
        _mm256_mulhi_epi16(v_lo, V_RED_COEFF)
    );
    
    __m256i g_lo = _mm256_add_epi16(
        _mm256_mulhi_epi16(y_lo, Y_COEFF),
        _mm256_add_epi16(
            _mm256_mulhi_epi16(u_lo, U_GREEN_COEFF),
            _mm256_mulhi_epi16(v_lo, V_GREEN_COEFF)
        )
    );
    
    __m256i b_lo = _mm256_add_epi16(
        _mm256_mulhi_epi16(y_lo, Y_COEFF),
        _mm256_mulhi_epi16(u_lo, U_BLUE_COEFF)
    );
    
    // Calculate RGB components (high 8 pixels)
    __m256i r_hi = _mm256_add_epi16(
        _mm256_mulhi_epi16(y_hi, Y_COEFF),
        _mm256_mulhi_epi16(v_hi, V_RED_COEFF)
    );
    
    __m256i g_hi = _mm256_add_epi16(
        _mm256_mulhi_epi16(y_hi, Y_COEFF),
        _mm256_add_epi16(
            _mm256_mulhi_epi16(u_hi, U_GREEN_COEFF),
            _mm256_mulhi_epi16(v_hi, V_GREEN_COEFF)
        )
    );
    
    __m256i b_hi = _mm256_add_epi16(
        _mm256_mulhi_epi16(y_hi, Y_COEFF),
        _mm256_mulhi_epi16(u_hi, U_BLUE_COEFF)
    );
    
    // Add rounding offset and shift
    r_lo = _mm256_srai_epi16(_mm256_add_epi16(r_lo, ROUND_OFFSET), 8);
    g_lo = _mm256_srai_epi16(_mm256_add_epi16(g_lo, ROUND_OFFSET), 8);
    b_lo = _mm256_srai_epi16(_mm256_add_epi16(b_lo, ROUND_OFFSET), 8);
    r_hi = _mm256_srai_epi16(_mm256_add_epi16(r_hi, ROUND_OFFSET), 8);
    g_hi = _mm256_srai_epi16(_mm256_add_epi16(g_hi, ROUND_OFFSET), 8);
    b_hi = _mm256_srai_epi16(_mm256_add_epi16(b_hi, ROUND_OFFSET), 8);
    
    // Pack to 8-bit with saturation
    __m256i r = _mm256_packus_epi16(r_lo, r_hi);
    __m256i g = _mm256_packus_epi16(g_lo, g_hi);
    __m256i b = _mm256_packus_epi16(b_lo, b_hi);
    __m256i a = ALPHA_VALUE;
    
    // Interleave BGRA
    __m256i bg_lo = _mm256_unpacklo_epi8(b, g);
    __m256i ra_lo = _mm256_unpacklo_epi8(r, a);
    __m256i bg_hi = _mm256_unpackhi_epi8(b, g);
    __m256i ra_hi = _mm256_unpackhi_epi8(r, a);
    
    __m256i bgra_0 = _mm256_unpacklo_epi16(bg_lo, ra_lo);
    __m256i bgra_1 = _mm256_unpackhi_epi16(bg_lo, ra_lo);
    __m256i bgra_2 = _mm256_unpacklo_epi16(bg_hi, ra_hi);
    __m256i bgra_3 = _mm256_unpackhi_epi16(bg_hi, ra_hi);
    
    // Store results
    _mm256_storeu_si256((__m256i*)(output + 0), bgra_0);
    _mm256_storeu_si256((__m256i*)(output + 32), bgra_1);
    _mm256_storeu_si256((__m256i*)(output + 64), bgra_2);
    _mm256_storeu_si256((__m256i*)(output + 96), bgra_3);
}

} // namespace v4l2
} // namespace ndi_bridge
