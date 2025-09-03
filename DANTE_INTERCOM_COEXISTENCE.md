# Dante and Intercom Coexistence

## Overview

Both Dante audio bridge and VDO.Ninja intercom use PipeWire for audio processing. This document explains how they interact and potential conflicts.

## Architecture

### Intercom (VDO.Ninja)
- Uses PipeWire with PulseAudio compatibility layer
- No specific sample rate requirement (adapts to system default)
- Runs Chrome in Xvfb with PipeWire for audio
- Uses CSCTEK USB Audio device for headset
- Operates independently of system-wide audio configuration

### Dante Audio Bridge  
- Uses PipeWire for adaptive resampling
- REQUIRES 96kHz sample rate (Dante standard)
- Uses Arturia/Focusrite USB interface
- Requires system-wide PTP sync (conflicts with NDI PTP)

## Conflict Analysis

### 1. PipeWire Instance Conflict
**Issue**: Both services try to start their own PipeWire instances

**Current Implementation**:
- Intercom starts PipeWire in its script (`ndi-bridge-intercom-pipewire`)
- Dante expects system-wide PipeWire service

**Resolution**:
- Use system-wide PipeWire service for both
- Intercom script checks if PipeWire is already running
- Both services connect to the same PipeWire daemon

### 2. Sample Rate Conflict
**Issue**: Dante requires 96kHz, intercom typically uses 48kHz

**Impact**:
- When Dante is active: System forced to 96kHz
- Intercom audio will be resampled from 48kHz to 96kHz
- Slight increase in CPU usage and latency

**Resolution**:
- PipeWire's adaptive resampling handles this automatically
- Intercom continues to work at 96kHz (with resampling)
- No configuration changes needed

### 3. USB Device Conflict
**Issue**: Different USB devices for different purposes

**Current State**:
- Intercom: CSCTEK USB Audio (headset)
- Dante: Arturia/Focusrite (professional interface)

**Resolution**:
- No conflict - different devices
- Both can be active simultaneously
- PipeWire routes audio to appropriate devices

### 4. PTP Conflict (CRITICAL)
**Issue**: Dante requires PTPv1, NDI requires PTPv2

**Impact on Intercom**:
- Intercom doesn't use PTP directly
- But NDI streaming (if used with intercom) loses precision

**Current Resolution**:
- When Dante active: PTPv1 only (NDI degraded)
- When Dante inactive: PTPv2 for NDI
- Intercom unaffected by PTP choice

## Service Interaction Matrix

| Dante Active | Intercom Active | NDI PTP | Result |
|-------------|-----------------|---------|---------|
| No | No | PTPv2 ✅ | Normal NDI operation |
| No | Yes | PTPv2 ✅ | Intercom + precise NDI |
| Yes | No | PTPv1 ⚠️ | Dante works, NDI degraded |
| Yes | Yes | PTPv1 ⚠️ | Both work, NDI degraded |

## Configuration for Coexistence

### 1. System-Wide PipeWire Configuration

Create `/etc/pipewire/pipewire.conf.d/00-system.conf`:
```ini
context.properties = {
    # Support both sample rates
    default.clock.rate = 48000
    default.clock.allowed-rates = [ 48000 96000 ]
    
    # Adaptive resampling for clock differences
    default.clock.quantum = 1024
}
```

### 2. Modified Intercom Startup

Update `ndi-bridge-intercom-pipewire` to check for existing PipeWire:
```bash
# Check if PipeWire is already running (e.g., for Dante)
if pgrep -x pipewire >/dev/null; then
    echo "PipeWire already running, using existing instance"
else
    echo "Starting PipeWire for intercom..."
    pipewire &
    PIPEWIRE_PID=$!
fi
```

### 3. Service Dependencies

Ensure proper startup order in systemd:
```ini
# dante-bridge.service
[Unit]
After=pipewire.service
Wants=pipewire.service

# ndi-bridge-intercom.service  
[Unit]
After=pipewire.service
Wants=pipewire.service
```

## Usage Scenarios

### Scenario 1: Intercom Only
```bash
systemctl start ndi-bridge-intercom
# PipeWire runs at 48kHz
# NDI uses PTPv2 for precision
# No Dante functionality
```

### Scenario 2: Dante Only
```bash
systemctl start dante-bridge
# PipeWire runs at 96kHz
# Statime provides PTPv1
# NDI falls back to NTP
```

### Scenario 3: Both Active (Recommended Setup)
```bash
# Start system PipeWire first
systemctl start pipewire

# Start both services
systemctl start dante-bridge
systemctl start ndi-bridge-intercom

# Result:
# - Dante audio at 96kHz via Arturia
# - Intercom at 48kHz→96kHz resampled via CSCTEK
# - NDI degraded to NTP timing
```

## Best Practices

### For Production Deployments

1. **Decide Primary Use Case**:
   - Intercom + NDI precision → Don't enable Dante
   - Dante audio critical → Accept NDI timing degradation

2. **Separate Devices Recommended**:
   - Use separate NDI Bridge for Dante
   - Keep intercom on NDI-focused device

3. **Monitor Resources**:
   ```bash
   # Check CPU usage with both active
   top -p $(pgrep pipewire)
   
   # Monitor xruns
   pw-top
   ```

4. **Sample Rate Considerations**:
   - If only using intercom: Keep 48kHz default
   - If Dante is primary: Set 96kHz system-wide
   - Let PipeWire handle resampling

## Known Issues

1. **Increased CPU Usage**: Running both services with resampling uses more CPU
2. **Potential Latency**: Resampling adds ~5-10ms latency to intercom
3. **PTP Conflict**: Cannot have both PTPv1 and PTPv2 on same interface

## Troubleshooting

### Intercom No Audio with Dante Active
```bash
# Check if intercom streams are connected
pactl list sink-inputs
pactl list source-outputs

# Force reconnection
systemctl restart ndi-bridge-intercom
```

### High CPU Usage
```bash
# Reduce PipeWire quantum for lower CPU
pw-metadata -n settings 0 clock.quantum 2048
```

### Audio Glitches
```bash
# Check for xruns
journalctl -u pipewire -u dante-bridge -u ndi-bridge-intercom | grep xrun

# Increase buffer size
pw-metadata -n settings 0 clock.quantum 2048
```

## Conclusion

Dante and Intercom can coexist using shared PipeWire infrastructure. The main limitation is the PTP conflict affecting NDI precision when Dante is active. For optimal operation, use separate devices or accept NDI timing degradation when Dante is needed.