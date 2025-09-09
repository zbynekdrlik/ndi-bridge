# INTERCOM.md - Media Bridge Intercom Architecture

**SINGLE SOURCE OF TRUTH for Intercom Functionality**

## Current Status (2025-09-08) - ✅ WORKING WITH USER SESSION

**✅ Chrome Intercom WORKING with proper isolation**

**Current Reality**:
- Virtual devices created correctly ✓
- Chrome ONLY sees virtual devices (proper isolation) ✓
- Audio routing works properly ✓
- PipeWire 1.4.7 with user session architecture ✓
- Intercom tests: 8 passed, 1 USB HID control issue ✓

## CRITICAL: CSCTEK USB Audio Device (0573:1573)

**⚠️ MANDATORY**: The CSCTEK USB Audio device (ID 0573:1573) MUST be connected for intercom functionality.
- **Device**: USB Audio and HID headset
- **Vendor ID**: 0573 (Zoran Co. Personal Media Division)
- **Product ID**: 1573
- **ALSA Card**: Typically card 0 when connected
- **HID Control**: Requires root permissions for volume control

**Architecture**: 
- Chrome NEVER accesses hardware directly
- PipeWire loads USB audio as ALSA card
- Virtual devices (intercom-speaker/microphone) bridge to USB
- Chrome only uses virtual devices
- HID control interface requires elevated permissions

## Architecture Overview (v4.0 - User Session Model)

Media Bridge Intercom runs Chrome browser connected to VDO.Ninja for WebRTC communication. All components run as the `mediabridge` system user (UID 999).

### Audio Flow Design (PipeWire 1.4.7 Device Isolation)

```
USB Headset (CSCTEK 0573:1573)
    ↓
PipeWire (mediabridge user) + pw-container isolation
    ↓
Virtual Devices (intercom-speaker/microphone) 
    ↓
Chrome (isolated container - sees ONLY virtual devices)
    ↓
Direct audio routing via PipeWire links
```

## Core Components

### 1. Mediabridge User Environment
- **User**: mediabridge (UID 999)
- **Home**: `/var/lib/mediabridge/`
- **Runtime**: `/run/user/999/`
- **Chrome Profile**: `/var/lib/mediabridge/.chrome-profile/`

### 2. Services Architecture (User Session Model)

**User Session Services** (run as mediabridge user):
- `pipewire.service` - Main audio server (user session)
- `pipewire-pulse.service` - PulseAudio compatibility (user session)
- `wireplumber.service` - Session/policy manager (user session)

**System Services**:
- `media-bridge-intercom.service` - Chrome launcher (runs as mediabridge)
- `media-bridge-audio-manager.service` - Virtual device creator

**Key Configuration**:
- `loginctl enable-linger mediabridge` - Ensures user session persists
- XDG_RUNTIME_DIR: `/run/user/999/`
- PipeWire socket: `/run/user/999/pipewire-0`

### 3. Virtual Devices
Created by audio-manager for intended isolation:
- `intercom-speaker` - Virtual output (SINK)
- `intercom-microphone` - Virtual input (SOURCE)
- `intercom-mic-sink` - Helper sink for routing

**Current Implementation**: Chrome runs in PipeWire 1.4.7 container with device filtering.

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

#### `pw-container` (PipeWire 1.4.7 Isolation)
- Creates isolated audio namespace for Chrome
- Chrome sees only specified devices (intercom-speaker, intercom-microphone)
- Built-in PipeWire feature, no external scripts needed
- Proper solution for audio device filtering

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