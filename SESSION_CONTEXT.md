# Claude Session Context for Continuation

## How to Continue on New Box

After cloning the repository on your new box (10.77.9.21), start Claude with:
```bash
cd ~/devel/media-bridge-dev1
claude -c  # This will start a new conversation
```

Then provide this context to Claude:
```
Continue from previous session on fix-chrome-audio-isolation-issues-34-114 branch.
Previous work: Fixed PipeWire/audio issues, 14 intercom tests passing.
Task: Fix ALL 145+ intercom tests and complete audio category tests until 100% pass.
Test device: 10.77.8.119
See MIGRATION_STATUS.md for details.
```

## Current Session State

### Active Branch
- `fix-chrome-audio-isolation-issues-34-114`

### Last Working Test Device
- IP: 10.77.8.119 (or 10.77.8.111)
- SSH: root/newlevel

### What Was Fixed
1. **PipeWire service failure (exit 254)**
   - Disabled problematic 40-chrome-filter.conf
   - Fixed "cannot find label device-filter" error

2. **Audio Manager issues**
   - Changed from root to mediabridge user (UID 999)
   - Fixed XDG_RUNTIME_DIR to /run/user/999
   - Virtual devices now created successfully

3. **Test runner**
   - test-device.sh now uses --maxfail=0 by default

### Test Status
- ✅ 14 tests passing in test_intercom_audio.py
- ❌ 131+ tests still need to be checked and fixed
- 📋 Total: 145+ intercom tests, plus audio category

### Critical Files Modified
1. `/scripts/helper-scripts/media-bridge-intercom-control`
2. `/scripts/helper-scripts/media-bridge-audio-manager`
3. `/scripts/helper-scripts/pipewire-conf.d/40-chrome-filter.conf.disabled`
4. `/tests/test-device.sh`
5. `/docs/PIPEWIRE.md`

### Next Steps (CRITICAL - User's explicit instruction)
**"solve all tests till I test intercom again and again find out that it is still not working"**

1. Run ALL intercom tests:
   ```bash
   ./tests/test-device.sh 10.77.8.119 tests/component/intercom/
   ```

2. Run complete audio category:
   ```bash
   ./tests/test-device.sh 10.77.8.119 tests/component/audio/
   ```

3. Fix ALL failures systematically
4. Achieve 100% pass rate

### Key Architecture Reminders
- User session model: mediabridge (UID 999)
- Virtual devices: intercom-speaker, intercom-microphone
- Runtime dir: /run/user/999
- PipeWire 1.4.7 (upgraded from 1.0.5)

### Testing Philosophy
- "ONLY 100% test success can be considered 'working'!"
- Test on actual hardware, not just in theory
- Run tests with --maxfail=0 to see ALL failures

### Common Test Failures to Expect
- VNC/x11vnc process tests
- Chrome process verification
- Web interface control tests
- Service restart recovery
- Hardware detection tests

### Useful Commands for New Session
```bash
# Check service status on test box
ssh root@10.77.8.119 "systemctl status media-bridge-intercom"
ssh root@10.77.8.119 "sudo -u mediabridge pactl list sinks short"

# Monitor tests in background
./tests/test-device.sh 10.77.8.119 tests/component/intercom/ 2>&1 | tee test.log &
tail -f test.log | grep -E "passed|failed|ERROR"

# Check audio setup
ssh root@10.77.8.119 "/usr/local/bin/media-bridge-intercom-control status"
```

## Repository State
- All changes committed and pushed
- Clean working directory
- Latest commit: e724a3f (migration files)

## Important Notes for New Claude Instance
1. Read MIGRATION_STATUS.md first
2. Check INTERCOM.md for architecture
3. Review PIPEWIRE.md for audio system
4. Remember: mediabridge user, not root!
5. Virtual devices prevent hardware locking
6. User wants 100% tests passing, not partial success