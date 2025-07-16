# Thread Progress Tracking

## CRITICAL CURRENT STATE
**⚠️ EXACTLY WHERE WE ARE RIGHT NOW:**
- [x] Currently working on: Fixed black video issue in AVX2 conversion (v1.3.6)
- [ ] Waiting for: User to rebuild and test v1.3.6 on Ubuntu N100
- [ ] Blocked by: None - fix is ready for testing

## Implementation Status
- Phase: Linux USB Capture Support - Testing Phase
- Step: Testing AVX2 YUV-to-RGB fix for black video issue
- Status: TESTING_REQUIRED
- Version: 1.3.6

## Testing Status Matrix
| Component | Implemented | Unit Tested | Integration Tested | Multi-Instance Tested | 
|-----------|------------|-------------|--------------------|-----------------------|
| v4l2_capture | ✅ v1.3.5 | ❌ | ❌ | ❌ |
| v4l2_device_enumerator | ✅ v1.3.5 | ❌ | ❌ | ❌ |
| v4l2_format_converter | ✅ v1.3.6 | ❌ | ❌ | ❌ |
| v4l2_format_converter_avx2 | ✅ v1.3.6 | ❌ | ❌ | ❌ |
| main.cpp Linux support | ✅ v1.3.5 | ❌ | ❌ | ❌ |

## Test Environment
- **Hardware**: Intel N100 PC with NZXT Signal HD60 USB capture card
- **OS**: Ubuntu 24.04 LTS Live USB (via Ventoy)
- **Location**: ~/ndi-test/ndi-bridge/
- **Network**: SSH accessible at 10.77.9.183
- **See**: docs/UBUNTU_N100_TEST_SETUP.md for full setup details

## Recent Changes
### Fixed Black Video Issue (2025-07-16) - v1.3.6
1. **Root Cause Identified**: 
   - AVX2 code used `_mm256_mulhi_epi16` (shifts by 16 bits)
   - Scalar code uses shift by 8 bits
   - This caused all color values to be near zero
2. **Fix Applied**: 
   - Scaled all YUV-to-RGB coefficients by 256 in AVX2 implementation
   - Now matches the scalar code behavior
3. **Files Updated**: 
   - `v4l2_format_converter_avx2.cpp` - Scaled coefficients
   - `v4l2_format_converter_avx2.h` - Updated documentation
   - `CMakeLists.txt` - Version 1.3.6
   - `src/common/version.h` - Version 1.3.6

### Previous Fixes (2025-07-16) - v1.3.5
1. **Logger API Updates**: All compilation errors fixed
2. **Char Overflow Warning**: Fixed in AVX2 code
3. **Unused Variable Warning**: Fixed in main.cpp
4. **Signed/Unsigned Comparison**: Fixed in v4l2_capture.cpp

## Test Results So Far
### Version 1.3.5 (Tested)
- ✅ Builds successfully on Ubuntu 24.04
- ✅ Detects NZXT Signal HD60 capture card
- ✅ Establishes NDI connection (2 clients connected)
- ✅ Low latency achieved (~16ms)
- ❌ **Black video output** - no actual video visible
- ✅ Frame statistics working (269 captured, 268 sent)

### Version 1.3.6 (Awaiting Test)
- Fixed AVX2 coefficient scaling issue
- Expected to show actual video content

## Next Steps for New Thread
1. **Rebuild and Test v1.3.6**:
   ```bash
   cd ~/ndi-test/ndi-bridge/build
   rm -rf *
   export NDI_SDK_DIR="$HOME/ndi-test/NDI SDK for Linux"
   cmake ..
   make -j$(nproc)
   cd bin
   sudo ./ndi-bridge --device /dev/video0 --ndi-name "NZXT-v1.3.6"
   ```

2. **Verify Fix**:
   - [ ] Check version shows 1.3.6
   - [ ] Verify video shows actual content (not black)
   - [ ] Check CPU usage (<10% for 1080p60)
   - [ ] Test all formats if possible

3. **If Video Still Black**:
   - Try disabling AVX2: `export DISABLE_AVX2=1`
   - Test with lower resolution
   - Check if NV12 format works better than YUYV

## Known Issues
1. **Buffer Size Question**: processYUV16_AVX2 writes 128 bytes for 16 pixels - needs review
2. **MJPEG Support**: Not implemented (requires libjpeg)
3. **Format Selection**: Cannot manually select format (auto-detected)

## PR Status
**PR #8**: [feat: Add Linux USB capture card support (V4L2)](https://github.com/zbynekdrlik/ndi-bridge/pull/8)
- Status: Open, awaiting v1.3.6 test results
- Version: 1.3.6
- Critical fix: AVX2 black video issue
- All compilation issues resolved

## Commands for Quick Reference
```bash
# SSH to Ubuntu N100
ssh ubuntu@10.77.9.183  # password: test123

# Check capture card
v4l2-ctl --list-devices
v4l2-ctl --device=/dev/video0 --list-formats-ext

# Monitor performance
htop

# View logs
sudo dmesg | tail -20

# Test with ffmpeg
ffmpeg -f v4l2 -i /dev/video0 -frames:v 1 test.jpg
```

## Last User Action
- Date/Time: 2025-07-16 12:30
- Action: Reported black video issue with v1.3.5
- Result: Root cause identified and fixed in v1.3.6
- Next Required: Test v1.3.6 build and report results
