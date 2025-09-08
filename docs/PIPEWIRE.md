# PipeWire Audio Architecture - Mediabridge User Model

## ⚠️ CRITICAL: SINK vs SOURCE Terminology

**NEVER CONFUSE THESE AGAIN (common mistake made 1000+ times!):**
- **SINK = OUTPUT = SPEAKER** (audio destination, where sound goes TO)
  - Chrome's "Speaker" dropdown shows SINKS
  - Created with: `module-null-sink`
  - Examples: `intercom-speaker`, HDMI outputs, USB headphones
  
- **SOURCE = INPUT = MICROPHONE** (audio origin, where sound comes FROM)
  - Chrome's "Microphone" dropdown shows SOURCES
  - Created with: `module-remap-source`, `module-virtual-source`
  - Examples: `intercom-microphone`, USB mic, capture devices

- **MONITOR** = Special SOURCE that captures a SINK's output
  - Every SINK has a `.monitor` SOURCE
  - Example: `intercom-speaker.monitor` captures speaker output

**Common Error**: Creating microphone as SINK → Chrome sees it in Speaker list!

## Executive Summary (v3.0 - Mediabridge Architecture)

Media Bridge uses a **single-user architecture** where all components run as the `mediabridge` system user (UID 999). This provides process isolation while simplifying the audio stack. PipeWire runs as a user session service under mediabridge, not as root.

**Key Achievement**: Eliminated complex multi-user audio routing. All Media Bridge services (Chrome, PipeWire, NDI tools) run as mediabridge user with proper systemd lingering.

## Architecture Overview

### Single-User Model
- **User**: `mediabridge` (UID 999, system user)
- **Groups**: audio, video, pipewire
- **Home**: `/var/lib/mediabridge/`
- **Runtime**: `/run/user/999/`
- **Session**: Persistent via `loginctl enable-linger`

### Why This Architecture?

1. **Ubuntu Default Compliance**: Follows Ubuntu 24.04's standard PipeWire deployment
2. **Security**: Services don't run as root
3. **Simplicity**: Single user owns all audio processes
4. **Compatibility**: Works with standard PipeWire packages

## Key Components

### 1. System Services
All services run as mediabridge user:
- `pipewire-system.service` - Core audio server
- `pipewire-pulse-system.service` - PulseAudio compatibility
- `media-bridge-intercom.service` - Chrome intercom
- `media-bridge-audio-manager.service` - Virtual device setup
- `media-bridge-permission-manager.service` - Access control (currently limited)

### 2. Virtual Audio Devices
Created for Chrome isolation attempt:
- `intercom-speaker` - Virtual output device
- `intercom-microphone` - Virtual input device
- `intercom-mic-sink` - Helper sink for microphone routing

**CURRENT LIMITATION**: Chrome can still see ALL devices because it runs as the same mediabridge user. True isolation requires either:
- WirePlumber with proper access control (requires D-Bus)
- Separate user for Chrome (complicates audio routing)
- Custom PipeWire filter module (not yet implemented)

### 3. USB Audio Detection
- Specific to CSCTEK/Zoran device (USB ID 0573:1573)
- Detected via `lsusb` polling
- Creates loopback connections when USB present
- Removes loopbacks when USB disconnected

### 4. Configuration Structure

```
/etc/pipewire/
├── pipewire-system.conf       # Main PipeWire config
└── pipewire-system.conf.d/
    ├── 10-media-bridge.conf   # Core settings
    └── 20-virtual-devices.conf # Virtual device definitions

/etc/wireplumber/              # Currently NOT used (D-Bus issues)
└── main.lua.d/
    └── *.lua                   # Isolation scripts (inactive)
```

## Service Dependencies

```
mediabridge user (UID 999)
├── pipewire-system.service
│   └── pipewire-pulse-system.service
├── media-bridge-audio-manager.service
├── media-bridge-permission-manager.service
└── media-bridge-intercom.service
```

## Known Issues and Limitations

### 1. Chrome Device Isolation NOT Working
**Problem**: Chrome shows all audio devices in dropdown, not just virtual ones
**Root Cause**: All processes run as same user (mediabridge)
**Attempted Solutions**:
- Permission manager script (limited effectiveness)
- WirePlumber rules (requires D-Bus, fails in headless)
- PipeWire filter module (configuration syntax issues)

**Current Workaround**: Chrome audio enforcer moves streams to correct devices after connection

### 2. No WirePlumber Session Manager
**Problem**: WirePlumber fails with exit code 70 (D-Bus unavailable)
**Impact**: 
- No automatic device routing
- No access control enforcement
- Manual ALSA device loading required

**Workaround**: `load-alsa-devices.sh` manually loads USB audio

### 3. Test Failures
- **63 tests failing** related to device isolation
- Virtual device tests fail because isolation not enforced
- Permission tests fail because no session manager

## Testing

### Test Categories
- **Audio System**: Basic PipeWire functionality ✓
- **Virtual Devices**: Device creation ✓, isolation ✗
- **USB Detection**: Device detection ✓, routing ✓
- **Chrome Integration**: Audio works ✓, isolation ✗

### Running Tests
```bash
# Test audio subsystem
./tests/test-device.sh <IP> tests/component/audio/

# Test intercom
./tests/test-device.sh <IP> tests/component/intercom/
```

## Troubleshooting

### Check Service Status
```bash
systemctl status pipewire-system
systemctl status media-bridge-intercom
journalctl -u pipewire-system -f
```

### Verify Audio Devices
```bash
# As mediabridge user
sudo -u mediabridge bash -c 'export XDG_RUNTIME_DIR=/run/user/999; pactl list sinks short'
sudo -u mediabridge bash -c 'export XDG_RUNTIME_DIR=/run/user/999; pactl list sources short'
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No audio | PipeWire not running | Check pipewire-system service |
| Chrome sees all devices | No isolation enforcement | Known limitation - workaround with enforcer |
| USB audio not detected | Device not recognized | Check USB ID matches 0573:1573 |
| Connection refused | Wrong XDG_RUNTIME_DIR | Use /run/user/999 for mediabridge |

## Future Improvements Needed

1. **Implement Proper Device Isolation**
   - Option A: Fix WirePlumber for headless (fake D-Bus)
   - Option B: Custom PipeWire access module
   - Option C: Separate user for Chrome with audio bridge

2. **Automatic Device Selection**
   - Chrome should auto-select virtual devices
   - Implement via Chrome preferences or WebRTC constraints

3. **Complete Test Coverage**
   - Fix isolation test expectations
   - Update tests for mediabridge architecture
   - Remove WirePlumber dependencies from tests

## Migration Notes

### From Root-Based System (v2.x)
1. All services moved from root to mediabridge user
2. Runtime directory changed: `/run/user/0` → `/run/user/999`
3. Home directory: `/root` → `/var/lib/mediabridge`
4. Chrome profile: `/root/.chrome-profile` → `/var/lib/mediabridge/.chrome-profile`

### Service File Changes
- Added `User=mediabridge` to all services
- Updated `Environment="XDG_RUNTIME_DIR=/run/user/999"`
- Removed root-specific paths and permissions

## Security Considerations

### Current State
- Services don't run as root ✓
- Chrome process isolated from system ✓
- Audio device isolation NOT enforced ✗

### Recommendations
1. **Upgrade to PipeWire 1.4.7** for proper isolation (script provided)
2. Use pw-container for Chrome sandboxing after upgrade
3. Monitor and audit audio stream connections

## PipeWire 1.4.7 Upgrade Path

An upgrade script is available at `scripts/helper-scripts/upgrade-pipewire-latest.sh` that:
- Builds PipeWire 1.4.7 from source with security features
- Installs pw-container tool for application isolation
- Configures security contexts for Chrome
- Provides TRUE device isolation (Chrome only sees virtual devices)

After upgrade, Chrome would run as:
```bash
pw-container --context=chrome --filter="media.class=*/Virtual" -- chromium-browser
```

This eliminates the current limitation where Chrome can see all devices.

## References
- [PipeWire Documentation](https://docs.pipewire.org/)
- [WirePlumber Documentation](https://pipewire.pages.freedesktop.org/wireplumber/)
- Ubuntu 24.04 PipeWire implementation
- Media Bridge Issue #117 (Mediabridge Architecture)