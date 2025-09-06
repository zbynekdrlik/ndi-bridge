# INTERCOM.md - Media Bridge Intercom Architecture

**SINGLE SOURCE OF TRUTH for Intercom Functionality**

## Critical Issue Status (2025-09-06)

**⚠️ CRITICAL BUG: Chrome sees ALL hardware devices instead of only virtual devices**

**Symptom**: Chrome device list shows:
- USB Audio devices directly (WRONG)
- HDMI outputs (WRONG)  
- Multiple "Intercom" entries (WRONG)
- Should ONLY show: `intercom-microphone` and `intercom-speaker`

**Impact**: Intercom completely non-functional - no audio input/output

## Architecture Overview

Media Bridge Intercom uses **virtual audio device isolation** to ensure Chrome ONLY accesses audio through controlled virtual devices, preventing:
1. Audio leakage to HDMI outputs (security requirement)
2. USB device locking by Chrome
3. Direct hardware access by browser

### Audio Flow Design

```
USB Headset (CSCTEK 0573:1573)
    ↓
PipeWire System Service
    ↓
Loopback Modules (media-bridge-audio-manager)
    ↓
Virtual Devices (intercom-speaker/microphone)
    ↓
Chrome (ISOLATED - should ONLY see virtual devices)
```

## Core Components

### 1. System-Wide PipeWire (`/etc/systemd/system/`)
- `pipewire-system.service` - Main audio server (root)
- `pipewire-pulse-system.service` - PulseAudio compatibility
- `wireplumber-system.service` - Session management
- Runtime: `/run/user/0/` with `XDG_RUNTIME_DIR=/run/user/0`

### 2. Virtual Devices (Created by audio-manager)
- `intercom-speaker` - Null sink for Chrome output
- `intercom-microphone` - Null sink (monitor = Chrome input)
- Settings: 256 samples @ 48kHz (~5.33ms latency)

### 3. Key Scripts (`/usr/local/bin/`)

#### `media-bridge-audio-manager`
- Creates virtual devices on startup
- Detects USB audio (CSCTEK specific)
- Creates loopback modules for routing
- Monitors Chrome stream connections

#### `media-bridge-intercom-pipewire`
- Starts Xvfb display (:99)
- Launches Chrome with VDO.Ninja
- Should enforce audio isolation flags
- Manages Chrome lifecycle

#### `media-bridge-intercom-monitor`
- Optional self-monitoring (mic → headphones)
- Ultra-low latency (32 samples)
- Volume control (0-100%)

## Current Problems Analysis (CONFIRMED)

### 1. Virtual Devices Created But Not Isolating
**Status**: Virtual devices exist but Chrome sees ALL devices
```bash
# Chrome can see these hardware devices (WRONG):
alsa_input.usb-CSCTEK_USB_Audio_and_HID  # USB microphone
alsa_input.usb-NZXT_Signal_HD60         # Capture card audio
alsa_output.usb-CSCTEK_USB_Audio        # USB headphones  
alsa_output.pci-0000_00_1f.3.hdmi       # HDMI output
```

**Root Cause**: No WirePlumber access control or Chrome isolation flags

### 2. Chrome Isolation Bypass
**Expected Chrome flags**:
```bash
--use-fake-device-for-media-stream  # Force virtual devices
--audio-output-channels=2
--audio-input-channels=1
```

**Problem**: Chrome still sees hardware devices directly

### 3. WirePlumber Policy Issues
**Expected**: Hardware devices hidden from Chrome
**Actual**: All devices exposed to all applications

## Test Failures (Must Fix)

Current tests **PASS** but don't detect real failures:

1. `test_virtual_devices_exist_in_pipewire` - Passes even if devices missing
2. `test_chrome_only_connects_to_virtual_devices` - Doesn't verify isolation
3. `test_hardware_devices_hidden_from_chrome` - Not actually checking Chrome's view

**Required Test Improvements**:
- Actually query Chrome's device list via DevTools protocol
- Verify ONLY 2 devices visible to Chrome
- Check device names match exactly
- Test audio flow end-to-end

## Configuration Files

### PipeWire (`/etc/pipewire/pipewire.conf.d/`)
- `10-media-bridge.conf` - Core settings
- `20-virtual-devices.conf` - Device definitions

### WirePlumber (`/etc/wireplumber/main.lua.d/`)
- `50-media-bridge.lua` - Routing policies
- Must configure: `["node.link-group"]` for isolation

## Debugging Commands

```bash
# Check virtual devices exist
pactl list sinks short | grep intercom

# Check Chrome's audio connections
pactl list clients | grep -A 10 chrome

# Monitor audio routing
pw-top

# Check loopback modules
pactl list modules | grep loopback

# Verify Chrome process flags
ps aux | grep chrome | grep -o -- '--[^ ]*audio[^ ]*'
```

## Solution Requirements

### What Must Be Fixed

1. **intercom-microphone must be a SOURCE, not a SINK**
   - Current: Created as sink, Chrome sees it as speaker
   - Fix: Use `module-virtual-source` or configure monitor properly
   - Result: Chrome sees one speaker, one microphone

2. **Hardware devices must be hidden from Chrome** (but NOT from ndi-display!)
   - Current: Chrome sees all ALSA devices
   - Cannot use: `--use-fake-device-for-media-stream` (bypasses PipeWire entirely)
   - Options:
     a. WirePlumber access policies (if possible)
     b. Suspend/hide hardware devices when Chrome starts
     c. Use highest priority for virtual devices

3. **ndi-display must keep HDMI access**
   - HDMI audio must remain available for ndi-display
   - Only Chrome/intercom should be isolated
   - Don't break existing HDMI routing!

## Fix Priority

1. **IMMEDIATE**: Fix intercom-microphone to be a proper SOURCE
2. **CRITICAL**: Hide hardware devices from Chrome (not ndi-display)  
3. **HIGH**: Verify tests catch all issues before declaring success
4. **MEDIUM**: Update Chrome launch flags if needed
5. **LOW**: Optimize latency settings

## Service Dependencies

```
user-runtime-dir@0.service
    └── pipewire-system.service
        ├── pipewire-pulse-system.service
        └── wireplumber-system.service
            └── media-bridge-audio-manager.service
                └── media-bridge-intercom.service
```

## Testing Requirements

Before declaring intercom "working":
1. Virtual devices MUST exist and be only devices Chrome sees
2. Audio MUST flow: USB mic → Chrome → VDO.Ninja → Chrome → USB headphones
3. No audio on HDMI outputs
4. Tests MUST fail when real problems exist
5. Manual testing with actual headset required

## Version History

- **v2.2.7**: Virtual device isolation attempted - FAILED
- **v2.2.6**: Service dependencies fixed - partial success
- **v2.2.5**: Initial PipeWire system-wide implementation

## References

- [PipeWire Virtual Devices](https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/Virtual-Devices)
- [WirePlumber Access Control](https://pipewire.pages.freedesktop.org/wireplumber/configuration/access.html)
- [Chrome Audio Isolation](https://developer.chrome.com/docs/extensions/reference/audio/)