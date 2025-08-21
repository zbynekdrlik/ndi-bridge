# Build State - v1.7.3 - 2025-08-21

## Current Status
- Build v1.7.3 completed but image has loop device lock issues
- Copy of image (ndi-bridge-v1.7.3.img) is corrupted and won't boot
- Need to rebuild after WSL restart

## Completed Fixes in v1.7.3

### 1. Binary Handling Fixed
- Build script now checks for binaries before starting
- Binaries copied BEFORE chroot (not inside) at correct paths
- Both ndi-bridge and ndi-display binaries included

### 2. Display System Fixes
- Removed framebuffer fallback completely (DRM-only)
- Stream assignment works immediately (no y/n confirmation)
- NDI discovery has double-check for stable stream list
- Stream numbering starts at 1 (not 0) to avoid conflicts
- FPS shows clean 1 decimal place (30.0 not 30.0097)
- Dashboard shows both monitor and NDI info on same line

### 3. Build Script Improvements
- Added comprehensive cleanup function to prevent loop locks
- Auto-builds binaries if missing
- Better error handling

## Files Modified

### Build Scripts
- `/build-image-for-rufus.sh` - Added binary checks and better cleanup
- `/scripts/build-modules/00-variables.sh` - Version 1.7.3
- `/scripts/build-modules/09-ndi-service.sh` - Copy ndi-bridge binary
- `/scripts/build-modules/09a-ndi-display-service.sh` - Copy ndi-display binary

### Display Code
- `/src/display/display_output.cpp` - Removed framebuffer, DRM-only
- `/src/display/main.cpp` - Fixed bitrate calculation
- `/src/display/status_reporter.h` - Fixed FPS precision
- `/src/display/ndi_receiver.cpp` - Improved discovery stability

### Helper Scripts
- `/scripts/helper-scripts/ndi-display-config` - Complete redesign
- `/scripts/helper-scripts/ndi-bridge-welcome` - Fixed dashboard display
- `/scripts/helper-scripts/ndi-bridge-welcome-loop` - Direct menu launch

### Documentation
- `/CLAUDE.md` - Standardized build commands

## Next Build (v1.7.4)

After WSL restart, run:
```bash
cd /mnt/c/Users/newlevel/Documents/GitHub/ndi-bridge

# Increment version to 1.7.4
# Edit scripts/build-modules/00-variables.sh

# Build image
sudo ./build-image-for-rufus.sh > build.log 2>&1 &

# Monitor progress
tail -f build.log | grep -E "BUILD|ERROR"
```

## Expected Results
- Clean build without loop device issues
- Both binaries included and working
- Display configuration menu working properly
- Stream switching reliable
- Dashboard showing complete information

## Testing Checklist
1. Flash with Rufus to USB
2. Boot device and check version on TTY2
3. Press 'D' from welcome screen
4. Verify stream list is consistent
5. Assign stream without confirmation
6. Verify dashboard shows: Mon: 1920x1080@60Hz │ NDI: 1920x1080 30.0fps 155Mbps
7. Switch streams to verify process management works