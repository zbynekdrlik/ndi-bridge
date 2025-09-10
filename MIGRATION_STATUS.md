# Media Bridge Migration Status

## Migration to newlevel@10.77.9.21:~/devel/media-bridge-dev1

### Current Branch
- **Branch**: `fix-chrome-audio-isolation-issues-34-114`
- **GitHub**: https://github.com/zbynekdrlik/ndi-bridge
- **Last Commit**: `059ae24` - Add ALSA device loading to audio manager

### Migration Instructions

**On your new development box (10.77.9.21), run:**

```bash
# Option 1: Use the migration script
scp newlevel@<current-host>:/home/newlevel/devel/ndi-bridge/migrate-to-new-box.sh ~/
chmod +x ~/migrate-to-new-box.sh
./migrate-to-new-box.sh

# Option 2: Manual commands
cd ~/devel
git clone https://github.com/zbynekdrlik/ndi-bridge media-bridge-dev1
cd media-bridge-dev1
git checkout fix-chrome-audio-isolation-issues-34-114
```

### Work Completed

1. **PipeWire Issues Fixed**:
   - Disabled problematic `40-chrome-filter.conf` (was causing exit code 254)
   - Fixed "cannot find label device-filter" error
   - Services now start successfully

2. **Audio Manager Fixed**:
   - Changed to use mediabridge user (UID 999) instead of root
   - Virtual devices now created: intercom-speaker, intercom-microphone
   - Fixed XDG_RUNTIME_DIR to /run/user/999

3. **Test Runner Fixed**:
   - `test-device.sh` now always uses `--maxfail=0` to run ALL tests
   - No longer stops on first failure

4. **14 Audio Tests Passing**:
   - All tests in `test_intercom_audio.py` now pass
   - Virtual devices properly configured
   - Control scripts working with mediabridge user

### CRITICAL PENDING WORK

**The user's explicit instruction: "solve all tests till I test intercom again and again find out that it is still not working"**

1. **Run ALL 145+ intercom tests** (not just 14):
   ```bash
   ./tests/test-device.sh 10.77.8.119 tests/component/intercom/
   ```

2. **Run complete audio category tests**:
   ```bash
   ./tests/test-device.sh 10.77.8.119 tests/component/audio/
   ```

3. **Fix ALL failing tests** in both categories

4. **Known remaining issues to investigate**:
   - VNC tests may be failing (x11vnc process)
   - Chrome process tests need verification
   - Web interface control tests
   - Integration tests
   - Service restart recovery tests

### Test Device
- **IP**: 10.77.8.119 (or appropriate test box)
- **SSH**: root/newlevel

### Key Architecture Points

- **User Session Model**: mediabridge user (UID 999) runs PipeWire
- **Virtual Devices**: intercom-speaker, intercom-microphone (prevent hardware locking)
- **Runtime Directory**: /run/user/999 (contains PipeWire socket)
- **Audio Manager**: /usr/local/bin/media-bridge-audio-manager
- **Control Script**: /usr/local/bin/media-bridge-intercom-control

### Files Modified in This Branch

1. `/scripts/helper-scripts/media-bridge-intercom-control` - Fixed user and device detection
2. `/scripts/helper-scripts/media-bridge-audio-manager` - Added ALSA device loading
3. `/scripts/helper-scripts/pipewire-conf.d/40-chrome-filter.conf.disabled` - Disabled problematic config
4. `/tests/test-device.sh` - Added --maxfail=0 by default
5. `/docs/PIPEWIRE.md` - Documented PipeWire 1.4.7 upgrade path

### Next Steps for New Claude Instance

1. **IMMEDIATELY** run ALL intercom tests to see full scope of failures
2. Analyze each failure category systematically
3. Fix root causes, not just symptoms
4. Verify fixes on actual hardware (10.77.8.119)
5. Ensure 100% test pass rate before declaring success

Remember: **"ONLY 100% test success can be considered 'working'!"**