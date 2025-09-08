# INTERCOM.md - Media Bridge Intercom Architecture

**SINGLE SOURCE OF TRUTH for Intercom Functionality**

## Current Status (2025-09-07) - ⚠️ PARTIAL FUNCTIONALITY

**⚠️ WARNING: Chrome audio device isolation NOT fully working**

**Current Reality**:
- Virtual devices created correctly ✓
- Chrome can see ALL audio devices (not just virtual) ✗ 
- Audio routing works via enforcer workaround ✓
- Tests failing due to isolation issues (63 failures) ✗

**Root Cause**: All services run as same `mediabridge` user, so Chrome has access to all devices that user can see. PipeWire's permission system requires WirePlumber, which needs D-Bus (unavailable in headless).

## Architecture Overview (v3.0 - Mediabridge Model)

Media Bridge Intercom runs Chrome browser connected to VDO.Ninja for WebRTC communication. All components run as the `mediabridge` system user (UID 999).

### Audio Flow Design

```
USB Headset (CSCTEK 0573:1573)
    ↓
PipeWire (mediabridge user)
    ↓
Virtual Devices (intercom-speaker/microphone)
    ↓
Chrome (same user - sees ALL devices)
    ↓
Chrome Audio Enforcer (moves streams to correct devices)
```

## Core Components

### 1. Mediabridge User Environment
- **User**: mediabridge (UID 999)
- **Home**: `/var/lib/mediabridge/`
- **Runtime**: `/run/user/999/`
- **Chrome Profile**: `/var/lib/mediabridge/.chrome-profile/`

### 2. System Services (All run as mediabridge)
- `pipewire-system.service` - Audio server
- `pipewire-pulse-system.service` - PulseAudio compatibility
- `media-bridge-intercom.service` - Chrome launcher
- `media-bridge-audio-manager.service` - Virtual device creator
- `media-bridge-permission-manager.service` - Access control (limited effect)

### 3. Virtual Devices
Created by audio-manager for intended isolation:
- `intercom-speaker` - Virtual output (SINK)
- `intercom-microphone` - Virtual input (SOURCE)
- `intercom-mic-sink` - Helper sink for routing

**Problem**: Chrome can enumerate all devices, not just virtual ones.

### 4. Key Scripts (`/usr/local/bin/`)

#### `media-bridge-intercom-fixed`
- Main Chrome launcher (replaces multiple versions)
- Starts Xvfb on display :88
- Launches Chrome with VDO.Ninja
- Runs as mediabridge user

#### `media-bridge-audio-manager`
- Creates virtual devices
- Detects USB audio (CSCTEK 0573:1573)
- Creates loopback connections
- Uses `pw-link` for routing

#### `chrome-audio-enforcer` (WORKAROUND)
- Monitors Chrome audio streams
- Forces streams to virtual devices
- Runs continuously to maintain routing
- Required because isolation doesn't work

#### `media-bridge-permission-manager`
- Attempts to restrict device access
- Limited effectiveness without WirePlumber
- Sets PipeWire permissions via pw-cli

## Known Issues and Limitations

### 1. Chrome Shows All Audio Devices ⚠️
**Problem**: Chrome dropdown shows USB, HDMI, and all system devices
**Impact**: 
- User confusion (which device to select?)
- Potential for selecting wrong device
- Tests fail expecting only virtual devices

**Root Cause**: Single-user architecture means Chrome has same permissions as PipeWire

**Attempted Fixes**:
1. WirePlumber rules → Fails without D-Bus
2. PipeWire filter module → Configuration syntax issues
3. Permission manager → Limited effect without session manager
4. pw-cli permissions → Not enforced properly

**Current Workaround**: chrome-audio-enforcer moves streams after connection

### 2. Microphone Shows "No Audio" in Chrome
**Problem**: Chrome may select wrong microphone or show "No Audio"
**Solution**: Manual selection of "intercom-microphone" required

### 3. Test Failures (63 tests)
Failing test categories:
- Device isolation tests (expect only virtual devices)
- Permission tests (expect enforcement)
- Virtual device tests (expect Chrome restrictions)

## Testing

### Manual Verification
```bash
# Check what devices Chrome can see (via VNC)
# Open Chrome DevTools → Console
navigator.mediaDevices.enumerateDevices().then(d => console.log(d))

# Verify services
systemctl status media-bridge-intercom
systemctl status pipewire-system

# Check audio devices
sudo -u mediabridge bash -c 'export XDG_RUNTIME_DIR=/run/user/999; pactl list sinks short'
```

### Automated Tests
```bash
# Run intercom tests (expect failures)
./tests/test-device.sh <IP> tests/component/intercom/

# Specific isolation tests (will fail)
./tests/test-device.sh <IP> tests/component/intercom/test_intercom_audio_isolation.py
```

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No audio in Chrome | Wrong device selected | Manually select intercom-microphone |
| Chrome shows all devices | No isolation | Known issue - use enforcer |
| Audio on wrong output | Stream not moved | Check chrome-audio-enforcer running |
| Chrome won't start | Display issues | Check Xvfb on :88 |

### Debug Commands
```bash
# Check Chrome process
ps aux | grep chrome | grep vdo.ninja

# Monitor audio routing
journalctl -u media-bridge-intercom -f

# Check enforcer
journalctl -t chrome-enforcer -f

# List audio streams
sudo -u mediabridge pw-cli ls Link
```

## Future Requirements

### 1. Implement True Device Isolation
**Options**:
- Fix WirePlumber for headless (fake D-Bus socket)
- Run Chrome as separate user with audio bridge
- Custom PipeWire module for filtering
- Use containerization (podman) for Chrome

### 2. Automatic Device Selection
- Pre-configure Chrome to use virtual devices
- Implement WebRTC constraints in VDO.Ninja URL
- Use Chrome policies for device selection

### 3. Fix Test Suite
- Update tests to match current architecture
- Remove assumptions about device isolation
- Add tests for enforcer workaround
- Document expected vs actual behavior

## Migration from Root Architecture

### What Changed
1. Chrome runs as mediabridge (was root)
2. Path changes:
   - Profile: `/root/.chrome-profile` → `/var/lib/mediabridge/.chrome-profile`
   - Runtime: `/run/user/0` → `/run/user/999`
3. Display changed from :99 to :88
4. All services run as mediabridge user

### What Didn't Work
1. Device isolation (still broken)
2. WirePlumber (D-Bus issues)
3. Permission enforcement (limited effect)

## Security Considerations

### Current Vulnerabilities
1. **No device isolation** - Chrome can access all audio hardware
2. **Stream hijacking** - Any mediabridge process can access audio
3. **No audit trail** - Permission changes not enforced

### Recommendations
1. **DO NOT use in production** without fixing isolation
2. Monitor audio streams for unexpected connections
3. Consider separate user for Chrome if security critical
4. Implement proper access control before deployment

## References
- [PipeWire Access Control](https://docs.pipewire.org/page_access.html)
- [WirePlumber Documentation](https://pipewire.pages.freedesktop.org/wireplumber/)
- [Chrome WebRTC Constraints](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
- Media Bridge Issue #34 (Chrome Audio Isolation)