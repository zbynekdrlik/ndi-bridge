## Root Cause Analysis: Why Tests Failed After Deployment

After deep investigation, I found **TWO circular dependencies** that were preventing PipeWire user services from starting:

### First Circular Dependency (Already Fixed)
```
user@999.service → After=multi-user.target
multi-user.target → Wants=media-bridge-intercom.service  
media-bridge-intercom.service → After=user@999.service
```
**Fix**: Removed `After=multi-user.target` from user@999.service override ✓

### Second Circular Dependency (Just Discovered and Fixed)
The real issue preventing deployment from working:

```
media-bridge-intercom.service → After=user@999.service
media-bridge-intercom.service → Restart=always (with 10s restart)
```

**What happened**:
1. At boot, systemd tries to start user@999.service
2. media-bridge-intercom.service is enabled and has `After=user@999.service`
3. When intercom fails (because PipeWire isn't ready), it auto-restarts
4. These continuous restart attempts block user@999.service from completing
5. user@999.service times out after 10 seconds
6. PipeWire user services never start

**Why it worked after manual intervention**:
- During manual testing, I likely stopped/disabled intercom service
- This broke the circular dependency temporarily
- After reboot without deployment, the issue returned

### Fixes Applied to Repository

1. **Fixed**: `/scripts/helper-scripts/media-bridge-intercom.service`
   - Removed `After=user@999.service`
   
2. **Fixed**: `/scripts/helper-scripts/migrate-pipewire-user.sh`
   - Updated sed command to not add user@999 dependency
   
3. **Fixed**: `/files/systemd/system/ndi-display@.service`
   - Removed `After=user@999.service`

### Key Learning
Services that depend on user sessions (`After=user@999.service`) should NOT:
- Be enabled at system boot level
- Have aggressive auto-restart policies
- Block the user session from starting

The intercom service should start independently of the user session, not wait for it.

### Verification Needed
After these fixes, we need to:
1. Build new image
2. Deploy to device
3. Reboot and verify user@999.service starts successfully
4. Run full test suite to confirm ~95 tests are fixed
