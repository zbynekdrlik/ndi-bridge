# Thread Progress Tracking

## CRITICAL CURRENT STATE
**⚠️ EXACTLY WHERE WE ARE RIGHT NOW:**
- [x] Currently working on: Fixed integer overflow warnings in AVX2 code (v1.3.7)
- [ ] Waiting for: User to rebuild and test v1.3.7 on Ubuntu N100
- [ ] Blocked by: None - fix is ready for testing

## Implementation Status
- Phase: Linux USB Capture Support - Testing Phase
- Step: Testing AVX2 overflow fix and black video fix
- Status: TESTING_REQUIRED
- Version: 1.3.7

## Testing Status Matrix
| Component | Implemented | Unit Tested | Integration Tested | Multi-Instance Tested | 
|-----------|------------|-------------|--------------------|-----------------------|
| v4l2_capture | ✅ v1.3.5 | ❌ | ❌ | ❌ |
| v4l2_device_enumerator | ✅ v1.3.5 | ❌ | ❌ | ❌ |
| v4l2_format_converter | ✅ v1.3.6 | ❌ | ❌ | ❌ |
| v4l2_format_converter_avx2 | ✅ v1.3.7 | ❌ | ❌ | ❌ |
| main.cpp Linux support | ✅ v1.3.5 | ❌ | ❌ | ❌ |

## Test Environment
- **Hardware**: Intel N100 PC with NZXT Signal HD60 USB capture card
- **OS**: Ubuntu 24.04 LTS Live USB (via Ventoy)
- **Location**: ~/ndi-test/ndi-bridge/
- **Network**: SSH accessible at 10.77.9.183
- **See**: docs/UBUNTU_N100_TEST_SETUP.md for full setup details

## Recent Changes
### Fixed Integer Overflow Warnings (2025-07-16) - v1.3.7
1. **Root Cause**: 
   - Coefficients scaled by 256 exceeded 16-bit signed range
   - Values like 516*256=132096 > 32767 (max int16)
2. **Fix Applied**: 
   - Scale coefficients by 32 instead of 256
   - Use `_mm256_mullo_epi16` with right shift by 11 total
   - All values now fit in 16-bit range
3. **Files Updated**: 
   - `v4l2_format_converter_avx2.cpp` - New scaling approach
   - `v4l2_format_converter_avx2.h` - Updated documentation
   - `CMakeLists.txt` - Version 1.3.7
   - `src/common/version.h` - Version 1.3.7

### Fixed Black Video Issue (2025-07-16) - v1.3.6
1. **Root Cause Identified**: 
   - AVX2 code used `_mm256_mulhi_epi16` (shifts by 16 bits)
   - Scalar code uses shift by 8 bits
   - This caused all color values to be near zero
2. **Fix Applied**: 
   - Scaled all YUV-to-RGB coefficients by 256 in AVX2 implementation
   - Now matches the scalar code behavior

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

### Version 1.3.6 (Not Tested)
- Fixed AVX2 coefficient scaling issue for black video
- Waiting for test results

### Version 1.3.7 (Awaiting Test)
- Fixed integer overflow warnings in AVX2 code
- Should show actual video content

## Next Steps for New Thread
1. **Rebuild and Test v1.3.7**:
   ```bash
   cd ~/ndi-test/ndi-bridge
   git pull
   cd build
   rm -rf *
   export NDI_SDK_DIR="$HOME/ndi-test/NDI SDK for Linux"
   cmake ..
   make -j$(nproc)
   cd bin
   sudo ./ndi-bridge --device /dev/video0 --ndi-name "NZXT-v1.3.7"
   ```

2. **Verify Fix**:
   - [ ] Check version shows 1.3.7
   - [ ] Verify no compilation warnings
   - [ ] Verify video shows actual content (not black)
   - [ ] Check CPU usage (<10% for 1080p60)
   - [ ] Test all formats if possible

3. **If Video Still Black**:
   - Try disabling AVX2: `export DISABLE_AVX2=1`
   - Test with lower resolution
   - Check if NV12 format works better than YUYV
   - Provide logs showing exact failure

## Known Issues
1. **Buffer Size Question**: processYUV16_AVX2 comment mentions 128 bytes but should be 64 bytes
2. **MJPEG Support**: Not implemented (requires libjpeg)
3. **Format Selection**: Cannot manually select format (auto-detected)

## PR Status
**PR #8**: [feat: Add Linux USB capture card support (V4L2)](https://github.com/zbynekdrlik/ndi-bridge/pull/8)
- Status: Open, awaiting v1.3.7 test results
- Version: 1.3.7
- Critical fixes: 
  - AVX2 black video issue (v1.3.6)
  - Integer overflow warnings (v1.3.7)
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

# Test with different formats
v4l2-ctl --device=/dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=NV12
```

## Last User Action
- Date/Time: 2025-07-16 14:00
- Action: Reported overflow warnings from GCC compiler
- Result: Fixed by changing scaling approach in v1.3.7
- Next Required: Test v1.3.7 build and report results
