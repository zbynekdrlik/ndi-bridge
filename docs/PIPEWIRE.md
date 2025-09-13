# PipeWire Audio Architecture - Mediabridge User Model

Note (2025-09): This repository now uses a headless user-session architecture for PipeWire. All previous references to `/run/pipewire` bind mounts, `user@999.service`, or setting `XDG_RUNTIME_DIR=/run/pipewire` are deprecated. The authoritative model is:
- User session: `mediabridge` (UID ≥ 1000, home `/home/mediabridge`), lingering enabled
- Services: `pipewire`, `pipewire-pulse`, and `wireplumber` run as systemd user units for `mediabridge`
- Runtime: Use `XDG_RUNTIME_DIR=/run/user/<uid>` implicitly from the user session; do not override it
- Project services that use audio run as user units and depend on PipeWire user services

Use official docs to validate configuration syntax and behavior:
- PipeWire: https://docs.pipewire.org/
- WirePlumber: https://pipewire.pages.freedesktop.org/wireplumber/

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

**CRITICAL COMMON ERROR (SOLVED MULTIPLE TIMES)**: Creating microphone as SINK → Chrome sees it in Speaker list!

**SOLUTION**: Always verify device types with `pw-cli list-objects | grep media.class`:
- `media.class = "Audio/Sink"` → Chrome Speaker dropdown
- `media.class = "Audio/Source"` → Chrome Microphone dropdown

**Correct Implementation**:
- `intercom-speaker` → `module-null-sink` → Creates proper SINK for Chrome output
- `intercom-microphone` → `module-virtual-source` → Creates proper SOURCE for Chrome input (verify with pw-cli!)

**Debug Commands**:
```bash
# Verify device types (run this after every change)
sudo -u mediabridge pw-cli list-objects | grep -A3 "intercom-speaker\|intercom-microphone"
```

## CRITICAL DEVELOPMENT RULE: Official Documentation Verification

**MANDATORY**: ALL PipeWire/WirePlumber configuration changes MUST be verified against official documentation:
- https://docs.pipewire.org/ (PipeWire official docs)
- https://pipewire.pages.freedesktop.org/wireplumber/ (WirePlumber official docs)
- NO configuration should be implemented without verifying syntax and approach in official sources
- ALWAYS test configuration changes incrementally to avoid breaking working systems

## Executive Summary (v3.2 - PipeWire 1.4.7 User Mode)

Media Bridge uses **PipeWire 1.4.7** running as a dedicated `mediabridge` user (UID 999) with proper user session management. This architecture improves security by eliminating root audio processing while maintaining the required 5.33ms latency.

**Key Points**:
- ✅ PipeWire runs as dedicated `mediabridge` user (not root)
- ✅ Upgraded to PipeWire 1.4.7 via Rob Savoury's PPA
- ✅ Ubuntu 24.04 user-session architecture (systemd --user)
- ✅ Realtime scheduling (rtprio 95) for low latency
- ✅ WirePlumber Chrome isolation configuration (user scope)
- ✅ Migration script for existing deployments

## Architecture Overview

### User Session Architecture (current)
- User: `mediabridge` (UID ≥ 1000, regular user)
- Groups: audio, video, render, input
- Home: `/home/mediabridge/`
- Runtime: `/run/user/<uid>/` (provided by systemd user session)
- Session: Persistent via `loginctl enable-linger mediabridge`
- Chrome Profile: `/var/lib/mediabridge/chrome-profile/`

### Why This Architecture?

1. **Security**: No root audio processing - all audio runs as unprivileged user
2. **Ubuntu Compliance**: Follows Ubuntu 24.04's ConditionUser=!root requirement
3. **Process Isolation**: mediabridge user has minimal permissions
4. **Performance**: Maintains 5.33ms latency with realtime scheduling
5. **Compatibility**: Works with standard Ubuntu PipeWire packages

## Key Components

### 1. User Session Services (default Ubuntu model)
Managed by systemd --user for the `mediabridge` user:

- pipewire.service — Core audio server
- pipewire-pulse.service — PulseAudio compatibility layer
- wireplumber.service — Session and policy manager

Location: `/usr/lib/systemd/user/` or `/lib/systemd/user/`
Enablement: symlinks under `/home/mediabridge/.config/systemd/user/default.target.wants/`

### 2. Project User Units (running under mediabridge)
- media-bridge-intercom.service — Chrome intercom (user unit)
- ndi-display@.service — NDI display output (user unit)
- ndi-capture.service — runs as system unit but does not set XDG overrides (uses standard env)

### 2. Virtual Audio Devices
Created with blackhole approach for proper isolation:
- `intercom-speaker` - Virtual output device (null sink for Chrome audio output)
- `intercom-microphone` - Virtual input device (remap-source from blackhole monitor)
- `intercom-mic-blackhole` - Blackhole sink for microphone (prevents HDMI routing)
- `usb-audio-blackhole` - Default blackhole sink (prevents audio leakage)

**Implementation Details**:
- Blackhole sinks created with `module-null-sink` to prevent audio going to wrong outputs
- Microphone created as proper SOURCE using `module-remap-source` from blackhole monitor
- Static routing properties: `node.dont-reconnect=true`, `sink_dont_move=true`, `source_dont_move=true`
- Cleanup script removes duplicate nodes before setup

**CURRENT LIMITATION**: Chrome can still ENUMERATE all devices (shows 29+ in dropdown) but audio routing works correctly. Device enumeration isolation requires:
- WirePlumber with proper access control (requires D-Bus)
- Separate user for Chrome (complicates audio routing)
- pw-container tool from PipeWire 1.4.7 (available but not yet integrated)

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

## User Mode Configuration Details

### Service Enablement
Enabled by creating symlinks in mediabridge's user wants directory:
`/home/mediabridge/.config/systemd/user/default.target.wants/`

### WirePlumber Chrome Isolation
Configured via `/home/mediabridge/.config/wireplumber/wireplumber.conf.d/50-chrome-isolation.conf`:
```json
{
  "wireplumber.profiles": {
    "main": {
      "monitor.access": {
        "rules": [{
          "matches": [{"application.process.binary": "~chrome"}],
          "actions": {
            "update-props": {
              "media.allowed": ["intercom-speaker", "intercom-microphone.monitor"]
            }
          }
        }]
      }
    }
  }
}
```

## Resolved Issues (v3.2)

### ✅ Chrome Device Isolation Working
**Solution**: WirePlumber 0.5 JSON configuration restricts Chrome to virtual devices
**Implementation**: Chrome can only see `intercom-speaker` and `intercom-microphone`

### ✅ WirePlumber Session Manager Running
**Solution**: User session with loginctl linger provides proper D-Bus environment
**Impact**: Automatic device routing and access control now working

### Test Suite Updates
- **New test files** for user mode architecture:
  - `test_pipewire_user_mode.py` - User session tests
  - `test_intercom_user_mode.py` - Chrome profile and permissions
  - `test_pipewire_migration.py` - Migration script validation
- **Legacy tests** marked as expected failures in `test_unified_pipewire_legacy.py`
- **100+ new tests** for user mode features

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
# Check user session
systemctl status user@999

# Check PipeWire user services
sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user status pipewire
sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 systemctl --user status wireplumber

# Check system services
systemctl status media-bridge-intercom
systemctl status ndi-display@0
journalctl -u pipewire-system -f
```

### Verify Audio Devices
```bash
# As mediabridge user (recommended)
sudo -u mediabridge pactl list sinks short
sudo -u mediabridge pactl list sources short
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No audio | PipeWire not running | Check `systemctl --user -M mediabridge@ status pipewire` |
| Chrome sees all devices | WirePlumber config not loaded | Check `/var/lib/mediabridge/.config/wireplumber/` |
| USB audio not detected | Device permissions | Ensure mediabridge in audio group |
| Connection refused | User session not active | Check `loginctl user-status mediabridge` and `sudo -u mediabridge systemctl --user status pipewire` |
| Permission denied | Wrong user/group | Services must run as mediabridge:audio |

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

## Migration from Root to User Mode

### Automatic Migration Script
For existing deployments, run:
```bash
/usr/local/bin/migrate-pipewire-user.sh
```

This script handles:
- Creating mediabridge user with UID 999
- Moving Chrome profile to `/var/lib/mediabridge/chrome-profile`
- Updating all service files
- Configuring realtime scheduling limits
- Setting up socket bind mounts
- Disabling old system services

### Manual Migration Steps
1. Create mediabridge user: `useradd --system --uid 999 --gid audio mediabridge`
2. Enable linger: `loginctl enable-linger mediabridge`
3. Move Chrome profile: `mv /tmp/chrome-vdo-profile /var/lib/mediabridge/chrome-profile`
4. Update service files to use `User=mediabridge`
5. Do not override XDG_RUNTIME_DIR in scripts; use user session
6. Create limits.conf for realtime scheduling
7. Restart all services

## Security Improvements

### Achieved Security Goals
- ✅ **No root audio processing** - All audio runs as mediabridge user
- ✅ **Process isolation** - mediabridge user has minimal permissions
- ✅ **Chrome sandboxing** - Browser runs without root privileges
- ✅ **WirePlumber policies** - Chrome restricted to virtual devices
- ✅ **No direct hardware access** - Only PipeWire touches ALSA

### Realtime Scheduling
Configured via `/etc/security/limits.d/99-mediabridge.conf`:
```
@audio   -  rtprio     95
@audio   -  nice      -19
@audio   -  memlock    unlimited
```

### Socket Access Control
- Primary socket: `/run/user/999/pipewire-0` (user session)
- Bind mount: `/run/pipewire/pipewire-0` (system-wide access)
- Permissions: mediabridge:audio ownership

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
