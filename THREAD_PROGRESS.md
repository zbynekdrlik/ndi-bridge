# Thread Progress Tracking

## CRITICAL CURRENT STATE
**⚠️ EXACTLY WHERE WE ARE RIGHT NOW:**
- [x] Currently working on: Linux V4L2 ultra-low latency v1.8.0
- [ ] Waiting for: User to implement and test v1.8.0 code changes
- [ ] Blocked by: None - implementation plan ready

## Implementation Status
- Phase: **Linux V4L2 Ultra-Low Latency** - v1.8.0 PLANNED
- Step: Code modifications provided, awaiting implementation
- Status: IMPLEMENTATION_READY
- Version: 1.8.0 (planned)

## v1.8.0 Ultra-Low Latency Features ⏳
**CRITICAL OPTIMIZATIONS PLANNED**:
- ✅ Direct YUYV support without BGRA conversion
- ✅ Zero-copy mode for YUV formats
- ✅ Ultra-low buffer count (3 minimum)
- ✅ Real-time scheduling support
- ✅ Format priority (UYVY > YUYV > NV12)
- ✅ DMABUF preparation for future zero-copy
- ✅ New command-line options:
  - `--ultra-low-latency`
  - `--zero-copy`
  - `--realtime [priority]`

**Key Changes**:
1. **v4l2_capture.h**: Updated with new methods and members
2. **v4l2_capture.cpp**: Critical sections to modify:
   - Format priority vector
   - findBestFormat() with NDI-optimized selection
   - sendFrameDirect() for zero-copy
   - processFrame() with zero-copy path
   - Real-time scheduling support
3. **main.cpp**: New command-line options
4. **version.h**: Updated to 1.8.0

## Performance Expectations
- **Current v1.7.1**: ~8-12 frames latency
- **v1.8.0 Multi-threaded**: ~6-8 frames (with zero-copy YUV)
- **v1.8.0 Single-threaded**: ~4-6 frames
- **v1.8.0 Ultra-low latency**: ~2-3 frames (target)

## NDI Format Support (Verified)
- **UYVY**: Native, zero-copy
- **YUYV**: Converted to UYVY with AVX2 (in NDI sender)
- **BGRA/BGRX/RGBA/RGBX**: Native
- **NV12**: Requires conversion (avoid)

## Implementation Steps
1. Apply v4l2_capture.h changes ✅ (committed)
2. Apply v4l2_capture.cpp critical changes
3. Apply main.cpp modifications
4. Compile and test basic functionality
5. Test with 60fps camera:
   - Normal mode baseline
   - `--zero-copy` mode
   - `--ultra-low-latency` mode
   - `--ultra-low-latency --realtime 80`
6. Measure round-trip latency for each mode
7. Verify zero-copy frames in stats

## Test Commands
```bash
# Baseline test
./ndi-bridge -d /dev/video0 -n "Test" -v

# Zero-copy test
./ndi-bridge -d /dev/video0 -n "Test" -v --zero-copy

# Ultra-low latency test
./ndi-bridge -d /dev/video0 -n "Test" -v --ultra-low-latency

# Maximum performance test
./ndi-bridge -d /dev/video0 -n "Test" -v --ultra-low-latency --realtime 80
```

## Repository State
- Main branch: v1.6.7
- Current branch: fix/linux-v4l2-latency (v1.8.0 planned)
- PR: Not created yet
- Windows latency: 8 frames ✅
- Linux latency: 8-12 frames (v1.7.1)
- Target latency: 2-3 frames (v1.8.0)

## Next Steps
1. User implements code changes from artifacts
2. Compile and fix any build errors
3. Test all modes with latency measurements
4. If 2-3 frames achieved, create PR
5. Otherwise, investigate further optimizations:
   - DMABUF implementation
   - Kernel bypass techniques
   - Custom V4L2 driver modifications

## Key Insights
- BGRA conversion is the main latency culprit
- YUV formats (UYVY/YUYV) can go direct to NDI
- Most USB devices output YUYV (not UYVY)
- NDI sender already handles YUYV→UYVY with AVX2
- Zero-copy YUV path should save 3-5 frames

## Quick Reference
- Current version: 1.8.0 (planned)
- Branch: fix/linux-v4l2-latency
- Files to modify: 3 (v4l2_capture.cpp, main.cpp, version.h)
- v4l2_capture.h: Already updated ✅
- Critical feature: Zero-copy YUV support
