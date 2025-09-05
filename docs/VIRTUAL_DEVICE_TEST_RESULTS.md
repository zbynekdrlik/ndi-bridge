# Virtual Device Test Results and Security Issues

## Test Execution Summary
- **Date**: 2025-09-05
- **Device**: 10.77.8.110  
- **Test File**: tests/component/intercom/test_intercom_virtual_devices.py
- **Result**: 4 failed, 4 passed, 1 skipped

## Critical Security Issue Confirmed

### Issue #114: Chrome Audio Playing on HDMI
**STATUS: CONFIRMED - CRITICAL SECURITY BREACH**

Chrome audio is currently routing to HDMI output instead of being restricted to USB CSCTEK device:
- Chrome Sink Input #102 → Sink #53 (HDMI)
- This violates security requirement that intercom audio MUST only use USB CSCTEK

## Test Failures Analysis

### 1. test_virtual_devices_exist_in_pipewire - FAILED
**Issue**: Missing virtual microphone device
- ✅ `intercom-speaker` exists (Sink #76)
- ❌ `intercom-microphone` NOT found
- Only partial virtual device implementation

### 2. test_no_audio_on_hdmi_from_intercom - FAILED  
**Issue**: Chrome audio routing to HDMI (SECURITY BREACH)
- Chrome Sink Input #102 → HDMI Sink #53
- This is the critical security issue from #114
- Chrome should NEVER output to HDMI

### 3. test_virtual_devices_are_default_when_present - FAILED
**Issue**: HDMI is default sink instead of virtual device
- Current default: `alsa_output.pci-0000_00_1f.3.hdmi-stereo`
- Should be: `intercom-speaker`
- Virtual devices not being set as defaults

### 4. test_usb_hotplug_maintains_virtual_routing - FAILED
**Issue**: media-bridge-audio-manager service not running
- Service status: `inactive` (exit code 4)
- Service responsible for creating/managing virtual devices
- Without this service, virtual device routing fails

### 5. test_loopback_modules_active_with_usb - SKIPPED
**Reason**: No CSCTEK USB audio device detected
- Test requires USB audio hardware
- May indicate device disconnected or not recognized

## Root Causes Identified

### 1. Incomplete Virtual Device Implementation
- Only `intercom-speaker` created, missing `intercom-microphone`
- Virtual devices not set as system defaults
- Chrome not restricted to virtual devices

### 2. Audio Manager Service Not Running
- `media-bridge-audio-manager` service is inactive
- This service should create virtual devices and manage routing
- Service failure prevents proper audio isolation

### 3. Chrome Direct Hardware Access
- Chrome can see and use ALL PipeWire devices:
  - HDMI audio outputs
  - USB audio devices  
  - Virtual devices
- No policy restricting Chrome to virtual devices only

### 4. Default Audio Routing Issues
- System defaulting to HDMI instead of virtual devices
- PipeWire/WirePlumber not configured to prefer virtual devices
- No enforcement of device priorities

## Required Fixes

### Priority 1: Security Fix (Issue #114)
1. **Restrict Chrome to virtual devices only**
   - Implement WirePlumber policy to hide hardware from Chrome
   - Force Chrome to use virtual devices via launch parameters
   - Block Chrome from accessing HDMI sinks

### Priority 2: Complete Virtual Device Implementation (Issue #34)
1. **Create missing `intercom-microphone` device**
2. **Fix media-bridge-audio-manager service**
3. **Set virtual devices as defaults when present**
4. **Implement proper loopback routing**

### Priority 3: System Configuration
1. **Update Chrome launch script** to use `--audio-output-channels=2 --audio-input-channels=1`
2. **Configure WirePlumber** to enforce device access policies
3. **Set PipeWire defaults** to prefer virtual devices

## Test Coverage Notes

The new test file successfully detects:
- Missing virtual devices
- Chrome hardware access (security issue)
- Default device configuration problems
- Service status issues
- Loopback module configuration

These tests provide comprehensive coverage for issues #34 and #114.

## Next Steps

1. Fix media-bridge-audio-manager service
2. Create missing virtual microphone device
3. Implement WirePlumber policy for Chrome isolation
4. Update Chrome launch parameters
5. Re-run tests to verify fixes