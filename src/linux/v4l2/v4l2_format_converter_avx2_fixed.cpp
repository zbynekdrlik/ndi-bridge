// Temporary test file to verify the fix
// This shows the corrected processYUV16_AVX2 function

/*
The bug: The original code was writing 128 bytes for 16 pixels.
After the permutation, the data is arranged as:
- r, g, b, a: each contains 32 bytes (256 bits)
- r_lo128/g_lo128/b_lo128/a_lo128: first 16 bytes (pixels 0-15 packed)
- r_hi128/g_hi128/b_hi128/a_hi128: second 16 bytes (zeros or garbage)

When we unpack and interleave for BGRA:
- bg_lo_0, ra_lo_0: from first 8 bytes of lo128 vectors
- bg_hi_0, ra_hi_0: from second 8 bytes of lo128 vectors
- bg_lo_1, ra_lo_1: from first 8 bytes of hi128 vectors (garbage!)
- bg_hi_1, ra_hi_1: from second 8 bytes of hi128 vectors (garbage!)

The fix: Only process and store the lo128 vectors, which contain all 16 pixels.
*/

inline void V4L2FormatConverterAVX2::processYUV16_AVX2_FIXED(
    const __m256i& y_vec,
    const __m256i& u_vec,
    const __m256i& v_vec,
    uint8_t* output)
{
    // ... conversion code same as before until packing ...
    
    // Pack to 8-bit with saturation
    __m256i r = _mm256_packus_epi16(r_lo, r_hi);
    __m256i g = _mm256_packus_epi16(g_lo, g_hi);
    __m256i b = _mm256_packus_epi16(b_lo, b_hi);
    __m256i a = ALPHA_VALUE;
    
    // After packing, we have 16 pixels worth of data in the low 128 bits
    // The high 128 bits are not needed
    __m128i r_pixels = _mm256_castsi256_si128(r);
    __m128i g_pixels = _mm256_castsi256_si128(g);
    __m128i b_pixels = _mm256_castsi256_si128(b);
    __m128i a_pixels = _mm256_castsi256_si128(a);
    
    // Interleave BGRA for all 16 pixels (64 bytes total)
    // Process first 8 pixels
    __m128i bg_0 = _mm_unpacklo_epi8(b_pixels, g_pixels);
    __m128i ra_0 = _mm_unpacklo_epi8(r_pixels, a_pixels);
    __m128i bgra_lo = _mm_unpacklo_epi16(bg_0, ra_0);
    __m128i bgra_hi = _mm_unpackhi_epi16(bg_0, ra_0);
    
    _mm_storeu_si128((__m128i*)(output + 0), bgra_lo);  // pixels 0-3
    _mm_storeu_si128((__m128i*)(output + 16), bgra_hi); // pixels 4-7
    
    // Process second 8 pixels
    __m128i bg_1 = _mm_unpackhi_epi8(b_pixels, g_pixels);
    __m128i ra_1 = _mm_unpackhi_epi8(r_pixels, a_pixels);
    __m128i bgra_lo2 = _mm_unpacklo_epi16(bg_1, ra_1);
    __m128i bgra_hi2 = _mm_unpackhi_epi16(bg_1, ra_1);
    
    _mm_storeu_si128((__m128i*)(output + 32), bgra_lo2); // pixels 8-11
    _mm_storeu_si128((__m128i*)(output + 48), bgra_hi2); // pixels 12-15
    
    // Total: 64 bytes for 16 BGRA pixels
}
