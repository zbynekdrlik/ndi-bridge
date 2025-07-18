# Thread Progress Tracking

## CRITICAL CURRENT STATE
**⚠️ EXACTLY WHERE WE ARE RIGHT NOW:**
- [x] Currently working on: Linux V4L2 FPS issue fix (v2.1.1)
- [x] Waiting for: User to test FIXED v2.1.1 implementation with non-blocking poll
- [ ] Blocked by: Need to verify if 60 FPS and 8 frames latency achieved

## Implementation Status
- Phase: **Linux V4L2 Extreme Latency Fix** - v2.1.1 ready
- Step: FPS fix implemented, needs testing
- Status: IMPLEMENTED_NOT_TESTED (with non-blocking poll now)
- Version: 2.1.1 (FPS fix implemented)

## v2.1.1 FPS Fix Details
**Problem Found**:
- 1ms poll timeout was causing FPS drop to ~23-29 FPS
- Frames weren't being dropped, but capture timing was disrupted

**v2.1.1 Fix Includes**:
1. ✅ Non-blocking poll (0ms timeout) instead of 1ms
2. ✅ Thread yield to prevent CPU starvation
3. ✅ Better FPS warning detection (logs if <58 or >62 FPS)
4. ✅ All v2.1.0 extreme features still active:
   - 2 buffers (absolute minimum)
   - CPU affinity to core 3
   - RT priority 90
   - Memory locked with MCL_ONFAULT

## Quick Test Instructions
```bash
# Pull the latest fix and test:
cd ~/ndi-test/ndi-bridge
git pull
./test-n100.sh
```

## Previous Test Results (v2.1.0 with 1ms poll)
- Version loaded: ✅
- Memory locked: ✅ 
- Zero-copy: ✅
- **Issues found**:
  - FPS: 21-29 (NOT 60) ❌
  - No frames dropped but timing was wrong
  - 1ms poll was the culprit

## Expected with v2.1.1
- 60 FPS stable capture
- 2 buffers active
- RT priority 90
- CPU pinned to core 3
- Non-blocking poll with yield
- Target: 8 frames latency

## Linux V4L2 "EXTREME" Implementation
**v2.1.x Features**:
- ALWAYS 2 buffers (EXTREME minimum)
- ALWAYS non-blocking poll (0ms)
- ALWAYS CPU affinity (core 3)
- ALWAYS RT priority 90 (maximum)
- ALWAYS memory locked
- NO compromise on latency

## Repository State
- Main branch: v1.6.5
- Current branch: fix/linux-v4l2-latency (v2.1.1)
- Latest commit: Non-blocking poll fix
- Open PR: #15 (Linux latency fix)
- Windows latency: FIXED (8 frames) ✅
- Linux latency: TESTING v2.1.1 🎯

## Next Steps
1. **IMMEDIATE**: User runs test-n100.sh with v2.1.1
2. Verify 60 FPS in logs
3. Check if latency reaches 8 frames
4. If successful:
   - Update PR #15 with v2.1.1 results
   - Merge to main
5. If not successful:
   - Analyze remaining bottlenecks
   - Consider v2.2.0 with more extreme measures:
     - Pure busy-wait (no poll at all)
     - Custom kernel module
     - Direct hardware access

## Key Success Metrics
- FPS: 60 (stable, no drops)
- Latency: 8 frames or less
- 2 buffers active
- RT priority 90 working
- CPU usage: High on core 3 (expected)

## Command Line Format (v2.x)
**IMPORTANT**: v2.x uses positional arguments only:
```bash
./ndi-bridge [device] [ndi_name]
# Example:
./ndi-bridge /dev/video0 "NZXT HD60"
```

No flags like -d or -n in v2.x for simplicity!

## Polling Strategy Evolution
- v2.0.0: 0ms poll (original)
- v2.1.0: Pure busy-wait (caused issues)
- v2.1.0 fix1: 1ms poll (caused FPS drop)
- v2.1.1: Non-blocking poll (0ms) with yield ← CURRENT
