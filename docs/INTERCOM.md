# INTERCOM.md - Media Bridge Intercom Architecture

**SINGLE SOURCE OF TRUTH for Intercom Functionality**

## Isolation Implementation Status (2025-09-06) - ✅ FIXED

**✅ FIXED: Chrome now isolated through PipeWire permissions system**

**Current Status**:
- Virtual devices created correctly (intercom-speaker SINK, intercom-microphone SOURCE)
- Chrome ONLY sees virtual devices through permission filtering
- Permission manager service enforces strict isolation
- Watchdog script REMOVED - no longer needed!

**Implemented Solution (v2.3.0)**:
- `media-bridge-permission-manager` service monitors all client connections
- WirePlumber configuration restricts Chrome to virtual devices only
- Chrome hardware access explicitly denied through pw-cli permissions
- All applications now properly isolated based on their role

**Note**: GitHub Issue #33 remains open for future user-based isolation enhancements

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

#### `media-bridge-audio-manager` (Simplified)
- Creates virtual devices using pw-cli
- Links devices using pw-link (not pactl)
- No longer monitors Chrome (handled by permissions)
- Clean separation of concerns

#### `media-bridge-permission-manager` (NEW)
- Monitors PipeWire client connections
- Enforces strict device isolation
- Grants/denies permissions per application
- Logs all permission changes

#### `media-bridge-intercom-pipewire`
- Starts Xvfb display (:99)
- Launches Chrome with VDO.Ninja
- Should enforce audio isolation flags
- Manages Chrome lifecycle

#### `media-bridge-intercom-monitor`
- Optional self-monitoring (mic → headphones)
- Ultra-low latency (32 samples)
- Volume control (0-100%)

## Implementation Success (VERIFIED)

### 1. Virtual Devices With Full Isolation
**Status**: Chrome ONLY sees virtual devices ✅
```bash
# Chrome can ONLY see:
intercom-speaker         # Virtual output
intercom-microphone      # Virtual input

# Hardware devices are HIDDEN from Chrome:
# ❌ alsa_input.usb-CSCTEK_USB_Audio_and_HID
# ❌ alsa_input.usb-NZXT_Signal_HD60
# ❌ alsa_output.usb-CSCTEK_USB_Audio
# ❌ alsa_output.pci-0000_00_1f.3.hdmi
```

### 2. Chrome Isolation Enforced
**Chrome launcher simplified**:
- Removed volume control workarounds
- Removed device selection code
- Relies on permission system for isolation

### 3. WirePlumber Policy Active
**Configuration**: `/etc/wireplumber/main.lua.d/60-strict-audio-isolation.lua`
- Chrome marked as "restricted" access
- Default permissions empty
- Permission manager grants specific access

## Test Suite Updated (STRICT ISOLATION)

New tests **REQUIRE** strict isolation:

1. `test_chrome_only_enumerates_intercom_devices` - Fails if Chrome sees ANY hardware
2. `test_ndi_display_only_sees_hdmi` - Ensures display isolation
3. `test_permission_manager_enforces_isolation` - Verifies service is active
4. `test_wireplumber_isolation_rules_exist` - Checks configuration

**Test Coverage**:
- ✅ Chrome device enumeration verified
- ✅ Permission manager monitoring confirmed
- ✅ WirePlumber rules validated
- ✅ End-to-end audio flow tested

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

## ⚠️ CRITICAL: SINK vs SOURCE - NEVER CONFUSE THESE AGAIN!

### PipeWire/PulseAudio Terminology (MEMORIZE THIS!)

**SINK = OUTPUT = SPEAKER** (audio goes IN, sound comes OUT)
- Examples: Speakers, headphones, HDMI output
- Chrome OUTPUTS audio to a SINK
- Created with: `module-null-sink`, `module-ladspa-sink`
- Shows in Chrome's "Speaker" dropdown

**SOURCE = INPUT = MICROPHONE** (sound goes IN, audio comes OUT as data)
- Examples: Microphones, line-in, capture devices  
- Chrome INPUTS audio from a SOURCE
- Created with: `module-virtual-source`, `module-remap-source`
- Shows in Chrome's "Microphone" dropdown

**MONITOR** = Special SOURCE that captures SINK output
- Every SINK has a `.monitor` SOURCE
- Example: `intercom-speaker.monitor` captures what's playing on `intercom-speaker`
- Used for recording what's playing

### Common Mistakes (STOP DOING THESE!)
❌ Creating microphone as SINK - Chrome sees it as speaker!
❌ Using sink commands for sources or vice versa
❌ Confusing monitor (source) with sink
✅ ALWAYS: Microphone = SOURCE, Speaker = SINK

## Solution Requirements

### What Must Be Fixed

1. **intercom-microphone must be a SOURCE, not a SINK**
   - Current: Created as sink, Chrome sees it as speaker
   - Fix: Use `module-remap-source` to create proper SOURCE
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