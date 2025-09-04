# Unified PipeWire Architecture

## Executive Summary
Media Bridge uses a custom system-wide PipeWire implementation (v2.2.6) for audio management. Ubuntu/Debian only provides user-session PipeWire services that refuse to run as root, requiring us to create custom system services for our embedded/headless deployment.

**Critical Context**: Ubuntu 24.04 PipeWire packages include `ConditionUser=!root` which blocks system-wide usage. We bypass this with custom service files that don't have this restriction.

## Current Implementation

### System Architecture
- **Single PipeWire instance** running as root at `/run/user/0/`
- **Custom service files** replacing Ubuntu's user-session services
- **Virtual audio devices** to isolate Chrome from physical hardware
- **Trigger socket** for systemd activation without interfering with PipeWire's socket creation

### Service Components

| Service | Purpose | Key Configuration |
|---------|---------|-------------------|
| `pipewire-system.service` | Core audio server | Custom config at `/etc/pipewire/pipewire-system.conf` |
| `pipewire-system.socket` | Trigger for activation | Uses `/run/user/0/pipewire-trigger` (NOT the actual socket) |
| `pipewire-pulse-system.service` | PulseAudio compatibility | Provides `/run/user/0/pulse/native` |
| `wireplumber-system.service` | Session/policy management | Waits for PipeWire socket with 75s timeout |

### Critical Service Dependencies
```
user-runtime-dir@0.service (MUST start first)
    └── pipewire-system.service
        ├── pipewire-pulse-system.service
        └── wireplumber-system.service
            └── media-bridge-intercom.service
```

**Key Discovery**: `user-runtime-dir@0.service` recreates `/run/user/0/` on boot. PipeWire MUST start AFTER this service or its sockets will be deleted.

### Configuration Files

#### Custom PipeWire Config (`/etc/pipewire/pipewire-system.conf`)
- Explicitly creates sockets (default Ubuntu config has this commented out)
- Sets low-latency parameters (256 samples @ 48kHz)
- Configures real-time priority

#### Config Directory (`/etc/pipewire/pipewire.conf.d/`)
- `10-media-bridge.conf` - System-wide settings
- `20-virtual-devices.conf` - Virtual device definitions

#### WirePlumber Config (`/etc/wireplumber/main.lua.d/`)
- `50-media-bridge.lua` - Low-latency and monitoring settings
- `50-usb-audio.lua` - USB audio enablement

### Virtual Audio Devices

| Device | Purpose |
|--------|---------|
| `intercom-speaker` | Chrome audio output (prevents USB device locking) |
| `intercom-microphone` | Chrome audio input (isolates from physical mic) |

These are created by `media-bridge-audio-manager` and ensure Chrome never directly accesses physical USB devices.

## Audio Routing Flow
1. **Capture**: USB Microphone → PipeWire → Virtual Microphone → Chrome
2. **Playback**: Chrome → Virtual Speaker → PipeWire → USB Speaker  
3. **HDMI**: NDI Display → PipeWire → HDMI output (per display)

## Key Technical Details

### Why PipeWire Sockets Weren't Created on Boot (RESOLVED)
1. **Default Ubuntu config has socket creation commented out** (line 112 in `/usr/share/pipewire/pipewire.conf`)
2. **`user-runtime-dir@0.service` was deleting sockets** by recreating `/run/user/0/` after PipeWire started
3. **Solution**: Custom config with explicit socket creation + proper service ordering

### PipeWire Socket Behavior
- PipeWire creates its own sockets at `/run/user/0/pipewire-0` and `pipewire-0-manager`
- Does NOT support systemd socket passing (sd_listen_fds) - confirmed by PipeWire developers
- Trigger socket (`pipewire-trigger`) used only for activation, not actual communication
- PipeWire expects to create and manage its own sockets directly
- Socket permissions are 0666 (world-writable) as PipeWire handles security internally

### Service File Requirements
```ini
[Unit]
# CRITICAL: Start after runtime directory is created
After=sound.target pipewire-system.socket systemd-tmpfiles-setup.service user-runtime-dir@0.service
Requires=pipewire-system.socket user-runtime-dir@0.service

[Service]
Environment="XDG_RUNTIME_DIR=/run/user/0"
Environment="PIPEWIRE_RUNTIME_DIR=/run/user/0"
# Use custom config with explicit socket creation
ExecStart=/usr/bin/pipewire -c /etc/pipewire/pipewire-system.conf
```

## Performance Characteristics
- **Memory**: ~50MB for complete PipeWire stack
- **CPU**: <5% during active streaming
- **Latency**: 5.33ms buffer (256 samples @ 48kHz)
- **Startup**: All services active within 10 seconds of boot

## Verification Commands
```bash
# Check sockets exist
ls -la /run/user/0/pipewire*

# Verify all services running
systemctl is-active pipewire-system wireplumber-system pipewire-pulse-system

# Check virtual devices
pactl list sinks short | grep intercom

# Verify Chrome connection
pactl list clients | grep chrome
```

## Troubleshooting

### If Sockets Don't Exist After Boot
1. Check service order: `systemctl show pipewire-system | grep After`
2. Verify config: `grep sockets /etc/pipewire/pipewire-system.conf`
3. Check logs: `journalctl -u pipewire-system -b`
4. Ensure user-runtime-dir@0.service is in After= clause

### If WirePlumber Can't Connect
- Usually means PipeWire socket doesn't exist
- Check: `ls -la /run/user/0/pipewire-0`
- WirePlumber will retry for 75 seconds before failing
- Common cause: PipeWire started before user-runtime-dir@0.service

### Chrome Audio Issues
- Chrome requires virtual audio devices to avoid locking hardware
- Check virtual devices: `pactl list sources | grep intercom`
- Restart audio manager: `systemctl restart media-bridge-audio-manager`

## Version History
- **v2.2.6**: Final fix - proper service ordering with user-runtime-dir@0.service
- **v2.2.5**: Attempted various workarounds (auto-restart, extended timeouts)
- **v2.2.0**: Initial unified architecture implementation

## Summary
The unified PipeWire architecture provides reliable, low-latency audio for Media Bridge by:
1. Running a single system-wide instance (avoiding session conflicts)
2. Using virtual devices (preventing hardware locking)
3. Proper service dependencies (ensuring sockets persist)
4. Custom configuration (explicit socket creation)

This implementation is production-ready and has been verified to work reliably across multiple cold boots and reboots.