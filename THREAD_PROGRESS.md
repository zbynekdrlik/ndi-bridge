# Thread Progress Tracking

## CRITICAL CURRENT STATE
**⚠️ EXACTLY WHERE WE ARE RIGHT NOW:**
- [x] Currently working on: Diagnosing FPS issue with v2.1.3
- [x] Waiting for: User to test v2.1.3 with frame timing diagnostics
- [ ] Blocked by: Need to understand why device delivers <30 FPS instead of 60

## Implementation Status
- Phase: **Linux V4L2 Frame Rate Diagnosis** - v2.1.3 ready
- Step: Added detailed frame timing diagnostics
- Status: IMPLEMENTED_NOT_TESTED (diagnostics version)
- Version: 2.1.3 (frame timing diagnostics)

## v2.1.3 Diagnostic Details
**Problem**:
- Device configured for 60fps but only delivering 17-31 FPS
- No frames dropped, but frames arrive irregularly
- Need to understand if it's device/driver/USB issue

**v2.1.3 Diagnostics Include**:
1. ✅ Frame gap measurement (time between frames)
2. ✅ EAGAIN counting (busy-wait iterations)
3. ✅ Frame gap warnings (>25ms = missing frames)
4. ✅ Overall FPS tracking
5. ✅ Max frame gap reporting
6. ✅ Frame timing logs every 100 frames

## Quick Test Instructions
```bash
# Pull the latest diagnostics and test:
cd ~/ndi-test/ndi-bridge
git pull
./test-n100.sh
```

## What to Look For in v2.1.3 Logs
- **Frame gap warnings**: "Large frame gap detected: XXms"
- **EAGAIN counts**: Shows how many times we check between frames
- **Actual FPS**: Should show why it's not 60
- **Max frame gap**: Largest gap between frames

If frame gaps are consistently >16.67ms, the device isn't delivering 60fps.

## Test Results History
- v2.0.0: Implementation issues
- v2.1.0: 3 buffer bug
- v2.1.0 fix1: 23-29 FPS with 1ms poll
- v2.1.1: 16-28 FPS with 0ms poll + yield  
- v2.1.2: 17-31 FPS with pure busy-wait
- v2.1.3: TESTING with diagnostics

## Possible Root Causes
1. **USB Bandwidth** - USB 2.0 vs 3.0?
2. **Device/Driver** - Not actually capable of 60fps?
3. **Format Issue** - YUYV 1080p60 too much bandwidth?
4. **V4L2 Config** - Missing some setting?

## Linux V4L2 Implementation
**Current v2.1.x**:
- 2 buffers (minimum)
- Pure busy-wait
- CPU affinity to core 3
- RT priority 90
- Memory locked
- Zero-copy YUYV->NDI

## Repository State  
- Main branch: v1.6.5
- Current branch: fix/linux-v4l2-latency (v2.1.3)
- Latest commit: Frame timing diagnostics
- Open PR: #15 (Linux latency fix)
- Windows latency: FIXED (8 frames) ✅
- Linux FPS issue: DIAGNOSING 🔍

## Next Steps
1. **IMMEDIATE**: Run v2.1.3 and analyze frame timing
2. Check if frame gaps are consistent or variable
3. Look for patterns in EAGAIN counts
4. Determine if it's a device limitation

Possible solutions:
- Try lower resolution (720p60?)
- Try different format (NV12?)
- Check USB port (2.0 vs 3.0)
- Try different capture device

## Key Diagnostics to Report
- Frame gap pattern (consistent or variable?)
- Max frame gap value
- EAGAIN count patterns
- Any error messages
- USB port type being used

## Technical Note
At 60fps, frames should arrive every ~16.67ms. If we see consistent gaps of 33ms, the device is actually running at 30fps. Variable gaps suggest USB bandwidth or driver issues.