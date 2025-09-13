# INTERCOM.md - Media Bridge Intercom Architecture

**SINGLE SOURCE OF TRUTH for Intercom Functionality**

## Current Status

PipeWire and the intercom now run in a headless user-session under the `mediabridge` account (UID ≥ 1000) with lingering enabled. All references to `/run/pipewire` bind mounts are deprecated; the runtime comes from the user session (`XDG_RUNTIME_DIR=/run/user/<uid>`).

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

## Architecture Overview (v4.1 - Secure User Mode)

Media Bridge Intercom runs Chrome connected to VDO.Ninja for WebRTC communication. All components run as the dedicated `mediabridge` user (UID ≥ 1000) with proper privilege separation and a standard systemd user session.

### Audio Flow Design (PipeWire 1.4.7 with WirePlumber Isolation)

```
USB Headset (CSCTEK 0573:1573)
    ↓
PipeWire (mediabridge user, rtprio 95)
    ↓
Virtual Devices (intercom-speaker/microphone)
    ↓
WirePlumber Policy (50-chrome-isolation.conf)
    ↓
Chrome (restricted to virtual devices only)
    ↓
Direct audio routing via PipeWire links
```

## Core Components

### 1. Mediabridge User Environment
- **User**: mediabridge (UID ≥ 1000, regular user)
- **Groups**: audio, video, render, input
- **Home**: `/home/mediabridge/`
- **Runtime**: `/run/user/<uid>/` (from systemd user session)
- **Chrome Profile**: `/var/lib/mediabridge/chrome-profile/`
- **Realtime Limits**: rtprio 95, nice -19, unlimited memlock

### 2. Services Architecture (User Session Model)

**User Session Services** (run as mediabridge user):
- `pipewire.service` - Main audio server (user session)
- `pipewire-pulse.service` - PulseAudio compatibility (user session)
- `wireplumber.service` - Session/policy manager (user session)

**Project User Units**:
- `media-bridge-intercom.service` - user unit, depends on PipeWire user services
- `ndi-display@.service` - user unit for HDMI audio output (if used)

**Key Configuration**:
- `loginctl enable-linger mediabridge` - Ensures user session persists
- WirePlumber config: `/home/mediabridge/.config/wireplumber/wireplumber.conf.d/`

### 3. Virtual Devices
Created by audio-manager for intended isolation:
- `intercom-speaker` - Virtual output (SINK)
- `intercom-microphone` - Virtual input (SOURCE)
- `intercom-mic-sink` - Helper sink for routing

**Current Implementation**: Chrome runs in PipeWire 1.4.7 container with device filtering.

### 4. Key Scripts (`/usr/local/bin/`)

#### `media-bridge-intercom-launcher`
- Main Chrome launcher service coordinator
- Manages Chrome lifecycle and restarts
- Environment setup for user mode operation
- Runs as mediabridge user with audio group

#### `media-bridge-intercom-pipewire`
- Chrome launcher with PipeWire integration
- Starts Xvfb on display :99
- Launches Chrome with VDO.Ninja
- Uses `/var/lib/mediabridge/chrome-profile` for profile

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
sudo -u mediabridge systemctl --user status media-bridge-intercom
sudo -u mediabridge systemctl --user status pipewire

# Check audio devices
sudo -u mediabridge pactl list sinks short
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

## Implemented Security Features (v4.1)

### ✅ Device Isolation Achieved
**Solution**: WirePlumber 0.5 JSON configuration
- Chrome restricted to virtual devices only
- Hardware devices not accessible to Chrome
- Policy enforced at PipeWire level

### ✅ Secure Chrome Profile
- Located at `/var/lib/mediabridge/chrome-profile/`
- Owned by mediabridge:audio
- Pre-granted VDO.Ninja permissions
- No access to system directories

### ✅ Updated Test Suite
- New tests for user mode architecture
- Tests for Chrome profile migration
- Tests for realtime scheduling
- Tests focus on user session services (no bind mounts)

## Migration from Root to User Mode

### Automatic Migration
Run the migration script on existing systems:
```bash
/usr/local/bin/migrate-pipewire-user.sh
```

### What Changed
1. **User**: All services run as mediabridge (UID ≥ 1000) instead of root
2. **Paths**:
   - Chrome profile: `/tmp/chrome-vdo-profile` → `/var/lib/mediabridge/chrome-profile/`
   - Runtime: Provided by systemd user session (`/run/user/<uid>`); remove any overrides
   - PipeWire socket: System services → User session
3. **Services**: Removed pipewire-system, using standard user services
4. **Security**: Process isolation, no root audio processing

### What's Fixed
1. ✅ Device isolation via WirePlumber policies
2. ✅ WirePlumber runs with proper D-Bus in user session
3. ✅ Realtime scheduling for low latency
4. ✅ Chrome sandboxing without root privileges

## Security Improvements

### Resolved Security Issues
1. ✅ **Device isolation working** - Chrome restricted to virtual devices
2. ✅ **No root processes** - All audio runs as mediabridge user
3. ✅ **Process separation** - Chrome cannot access system resources
4. ✅ **WirePlumber policies** - Enforced at PipeWire level

### Security Best Practices
1. **Production ready** with user mode isolation
2. Realtime scheduling ensures low latency
3. Chrome runs with minimal privileges
4. Audio streams properly isolated

### Remaining Hardening Options
1. SELinux/AppArmor profiles for additional containment
2. Network namespace isolation for Chrome
3. Seccomp filters for system call restrictions
4. Audit logging for compliance requirements

## References
- [PipeWire Access Control](https://docs.pipewire.org/page_access.html)
- [WirePlumber Documentation](https://pipewire.pages.freedesktop.org/wireplumber/)
- [Chrome WebRTC Constraints](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
- Media Bridge Issue #34 (Chrome Audio Isolation)
