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

## CRITICAL DEVELOPMENT RULE: Official Documentation Verification

**MANDATORY**: ALL PipeWire/WirePlumber configuration changes MUST be verified against official documentation:
- https://docs.pipewire.org/ (PipeWire official docs)
- https://pipewire.pages.freedesktop.org/wireplumber/ (WirePlumber official docs)
- NO configuration should be implemented without verifying syntax and approach in official sources
- ALWAYS test configuration changes incrementally to avoid breaking working systems

## Executive Summary (v3.1 - PipeWire 1.4.7 User Session)

Media Bridge uses **PipeWire 1.4.7** with a **standard user session architecture** where PipeWire runs as the `mediabridge` user with loginctl lingering. This follows Ubuntu's standard approach for audio services.

**Key Achievements**: 
- ✅ Upgraded to PipeWire 1.4.7 (from 1.0.5) via Rob Savoury's PPA
- ✅ Follows Ubuntu/systemd best practices with user session services
- ✅ Automatic startup via loginctl lingering (no login required)
- ✅ All 58 audio tests passing (100% success rate)
- ✅ pw-container tool available for future Chrome isolation

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

### 1. User Session Services (NEW in v3.1)
Managed by systemd --user for mediabridge user:

- **pipewire.service** - Core audio server (PipeWire 1.4.7)
- **pipewire-pulse.service** - PulseAudio compatibility layer
- **wireplumber.service** - Session and policy manager
- **Location**: `/usr/lib/systemd/user/`
- **Enabled via**: `loginctl enable-linger mediabridge`

### 2. System Services
- **media-bridge-intercom.service** - Chrome intercom (system service running as mediabridge)

Services start automatically on boot via loginctl lingering.
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

## PipeWire 1.4.7 Upgrade (IMPLEMENTED)

### Standardized PPA-Based Installation
As of build module 08, Media Bridge now uses **Rob Savoury's PPA** for PipeWire 1.4.7:
- **Version**: 1.4.7-0ubuntu1~24.04.sav0
- **Method**: PPA installation during image build
- **Module**: `scripts/build-modules/08-pipewire-upgrade.sh`
- **Verification**: `media-bridge-verify-pipewire` helper script

### Why PPA Instead of Source Build?
1. **Faster builds**: No compilation required (saves 10+ minutes)
2. **Reproducible**: Same packages for every build
3. **Maintained**: Security updates via PPA
4. **Stable**: Well-tested packages for Ubuntu 24.04

### Key Features in 1.4.7
- Enhanced security context support
- pw-container tool for application sandboxing (if available)
- Improved virtual device handling
- Better Chrome isolation capabilities
- Performance improvements over 1.0.5

### Package Pinning
Packages are pinned to prevent accidental downgrades:
```
/etc/apt/preferences.d/pipewire-pin
Package: pipewire pipewire-* libpipewire-* libspa-*
Pin: version 1.4.7-0ubuntu1~24.04.sav0
Pin-Priority: 1001
```

### Migration from Source Build
The previous approach (`scripts/helper-scripts/upgrade-pipewire-latest.sh`) built from source but:
- Took 15+ minutes during runtime
- Required build dependencies on production image
- Made builds non-reproducible

The new PPA approach is integrated into the build process for consistency.

### Chrome Isolation with 1.4.7
After upgrade, Chrome isolation capabilities are enhanced:
```bash
# If pw-container is available:
pw-container --context=chrome --filter="media.class=*/Virtual" -- chromium-browser

# Current implementation uses flags:
chromium-browser --audio-output-channels=2 --audio-input-channels=1 --enable-exclusive-audio
```

### Verification
After build, verify PipeWire version:
```bash
media-bridge-verify-pipewire
# Should show: ✓ PipeWire version: 1.4.7 (correct)
```

## References
- [PipeWire Documentation](https://docs.pipewire.org/)
- [WirePlumber Documentation](https://pipewire.pages.freedesktop.org/wireplumber/)
- Ubuntu 24.04 PipeWire implementation
- Media Bridge Issue #117 (Mediabridge Architecture)