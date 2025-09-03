# Dante Clock Architecture for NDI Bridge

## Critical Understanding: Multiple Clock Domains

The NDI Bridge operates in a complex environment with **FOUR independent clock domains** that must be properly managed:

```
1. Dante Network Clock (PTPv1)
   - Master: Real Dante device (console/clock)
   - ndi-bridge: FOLLOWER ONLY via Statime (Inferno fork)
   - CRITICAL: Requires teodly/statime:inferno-dev branch
   - Upstream Statime only supports PTPv2!
   
2. NDI Network Clock (PTPv2) 
   - Separate from Dante
   - Used by LinuxPTP (ptp4l/phc2sys)
   - INCOMPATIBLE with Dante PTPv1
   
3. USB Audio Clock (Arturia)
   - Independent crystal oscillator
   - Typically ±50ppm accuracy
   - Cannot be slaved to network clocks
   
4. System Clock
   - Linux CLOCK_MONOTONIC
   - Free-running
```

## Critical PTP Version Incompatibility

**WARNING**: Dante uses PTPv1, but most PTP implementations only support PTPv2:

| Implementation | PTPv1 Support | PTPv2 Support | Dante Compatible |
|---------------|---------------|---------------|------------------|
| Upstream Statime | ❌ No | ✅ Yes | ❌ No |
| Inferno's Statime Fork | ✅ Yes | ✅ Yes | ✅ Yes |
| LinuxPTP (ptp4l) | ❌ No | ✅ Yes | ❌ No |
| Dante Devices | ✅ Yes | Some (AES67) | ✅ Yes |

**This is why we MUST use the Inferno fork of Statime (`teodly/statime:inferno-dev`)!**

## The Fundamental Problem

**Direct audio routing between these domains WILL FAIL** due to clock drift:

```bash
# THIS WILL FAIL - No clock compensation!
arecord -D dante | aplay -D plughw:arturia
```

Even tiny clock differences (50ppm = 0.005%) cause:
- Buffer underruns/overruns within minutes
- Clicks, pops, and dropouts
- Complete stream failure over time

## Why This Is Hard

### Professional Dante Devices Solution:
- Hardware clock recovery circuits
- USB interface slaves to Dante PTP
- Or uses ASRC (Asynchronous Sample Rate Converter) chips
- Examples: RME Digiface Dante, Focusrite RedNet

### Our Challenge:
- Software-only solution
- USB audio has independent clock
- Cannot slave USB to Dante in software
- Must handle drift in real-time

## The Correct Solution: Adaptive Resampling

### Option 1: PipeWire (Recommended)

PipeWire provides automatic clock drift compensation through adaptive resampling:

```bash
# PipeWire handles clock domains automatically
pw-record --target=dante --rate=96000 | \
  pw-play --target=alsa_output.usb-Arturia --rate=96000
```

**Advantages:**
- Automatic drift detection and compensation
- High-quality resampling (SPA algorithm)
- Already installed for intercom
- Handles multiple clock domains gracefully

**How it works:**
1. Monitors buffer fill levels
2. Detects clock drift between domains
3. Applies micro-resampling to compensate
4. Maintains constant latency

### Option 2: JACK with zita-ajbridge

JACK with zita-ajbridge provides professional adaptive resampling:

```bash
# Start JACK
jackd -d alsa -d hw:USB -r 96000 -p 512 -n 2

# Bridge Dante ALSA to JACK with resampling
zita-a2j -d dante -r 96000 -p 512 -n 2 -Q 32
```

**Advantages:**
- Professional quality resampling
- Proven in broadcast environments
- Very stable drift compensation

**Disadvantages:**
- Higher CPU usage
- More complex setup
- Additional latency

### Option 3: Periodic Restart (Fallback)

For systems without PipeWire/JACK:

```bash
# Restart every 30 minutes to prevent drift buildup
while true; do
    timeout 1800 sh -c 'arecord -D dante | aplay -D plughw:USB'
    sleep 1  # Brief gap to reset buffers
done
```

**Disadvantages:**
- Audio interruption every 30 minutes
- Not professional quality
- Only delays the problem

## Clock Configuration

### Statime Configuration (FOLLOWER MODE)

**CRITICAL**: ndi-bridge must NEVER become PTP master!

```toml
[ptp]
interface = "br0"
domain = 0
priority1 = 255  # Lowest - never become master
priority2 = 255  # Lowest - never become master
clock_class = 255  # Slave-only

[clock]
# Aggressive following of master
servo_pi_proportional = 0.7
servo_pi_integral = 0.3
step_threshold = 0.0001  # 100 microseconds
```

### Clock Priority in Dante Network

```
Preferred Master: Dedicated Dante clock device
     ↓
Acceptable Master: Dante-enabled mixing console  
     ↓
Fallback Master: Other Dante endpoint
     ↓
NEVER Master: ndi-bridge (our device)
```

## Monitoring Clock Health

### Check PTP Sync Status:
```bash
# Check if synced to master
statime-ctl status

# Monitor offset from master
watch 'statime-ctl offset'
```

### Monitor for Clock Drift:
```bash
# With PipeWire
pw-top  # Watch for xruns

# In system logs
journalctl -f | grep -E "underrun|overrun|xrun"
```

### Expected Values:
- PTP offset: < 1ms (typically < 100μs)
- Xruns: 0 (occasional xrun acceptable)
- Buffer fill: 40-60% (not 0% or 100%)

## Implementation Recommendations

### For Production Use:

1. **Use PipeWire** for clock drift compensation
2. **Configure Statime** as follower-only
3. **Monitor** for xruns and drift
4. **Set proper priorities** in Dante Controller
5. **Test** with real Dante master device

### Testing Procedure:

1. Connect ndi-bridge to Dante network with real master
2. Verify ndi-bridge is PTP follower:
   ```bash
   statime-ctl status | grep role  # Should show "follower"
   ```
3. Start audio bridge with PipeWire
4. Monitor for 1+ hours for drift/xruns
5. Verify no audio degradation over time

## Common Issues and Solutions

| Problem | Cause | Solution |
|---------|-------|----------|
| ndi-bridge becomes PTP master | Wrong priority config | Set priority1/2 = 255 |
| Audio drifts after minutes | No resampling | Use PipeWire/JACK |
| Clicks and pops | Clock drift | Enable adaptive resampling |
| NDI and Dante conflict | Both using PTP | Different domains (PTPv1 vs PTPv2) |
| USB device not syncing | Independent clock | Cannot sync - must resample |

## Summary

**The Reality**: You cannot eliminate clock drift between Dante and USB audio.

**The Solution**: Use adaptive resampling (PipeWire or JACK) to continuously compensate for drift.

**The Key**: ndi-bridge must be a PTP follower, never a master, in the Dante network.

This is not a limitation of our implementation - it's a fundamental physics problem that even professional hardware must solve using ASRC chips or clock recovery circuits. Our software solution using PipeWire provides equivalent functionality.