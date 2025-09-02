# Dante Audio Bridge Implementation

## Overview

The NDI Bridge includes professional Dante audio networking support, enabling seamless integration with Dante-based audio systems. This implementation uses the open-source Inferno Dante protocol implementation with PipeWire for adaptive resampling to handle clock domain differences.

## Primary Use Case

**Dante Network → USB Audio Interface (Arturia/Focusrite)**

The system receives audio from a Dante network and plays it through a USB audio interface at 96kHz with automatic clock drift compensation.

## Architecture

### Clock Domains

The system manages four independent clock domains:

1. **Dante PTPv1** - Network master clock (microsecond precision)
2. **USB Audio** - Independent hardware clock  
3. **System Clock** - Linux system time
4. **NDI PTPv2** - Separate from Dante (incompatible protocols)

### Clock Synchronization Strategy

- **Statime (Inferno fork)** - Syncs system to Dante PTPv1
- **PipeWire** - Provides adaptive resampling between domains
- **Configuration** - ndi-bridge always acts as PTP follower/slave

### Components

1. **Inferno** - Open-source Dante protocol implementation (ALSA plugin)
2. **Statime** - PTP daemon (requires Inferno fork for PTPv1)
3. **PipeWire** - Audio server with adaptive resampling
4. **dante-bridge** - Production service managing the audio pipeline

## Installation

The Dante audio bridge is automatically installed during the USB image build process. All components are compiled from source for optimal performance.

### Build Process

1. **Inferno Compilation**
   - Cloned from: https://github.com/teodly/inferno.git
   - Builds ALSA plugin: `libasound_module_pcm_inferno.so`
   - Installed to: `/usr/lib/x86_64-linux-gnu/alsa-lib/`

2. **Statime Compilation** 
   - **CRITICAL**: Uses Inferno fork for PTPv1 support
   - Cloned from: https://github.com/teodly/statime.git (branch: inferno-dev)
   - Builds PTP daemon with Dante PTPv1 support
   - Installed to: `/usr/local/bin/statime`

3. **PipeWire Installation**
   - Installed from Ubuntu repositories
   - Configured for 96kHz with adaptive resampling
   - Configuration: `/etc/pipewire/pipewire.conf.d/90-dante-bridge.conf`

## Configuration

### Main Configuration File

Location: `/etc/ndi-bridge/dante.conf`

```bash
# Network interface (uses bridge by default)
DANTE_INTERFACE=br0

# Number of audio channels (2 = stereo)
DANTE_CHANNELS=2

# Sample rate - MUST BE 96000 for professional Dante networks
DANTE_SAMPLE_RATE=96000

# Device name for Dante network
DANTE_DEVICE_NAME=ndi-bridge

# Enable auto-start
DANTE_ENABLED=true
```

### PTP Configuration

Location: `/etc/statime.conf`

Critical settings for PTP follower mode:
- `priority1 = 255` (lowest priority)
- `priority2 = 255` (never become master)
- `clock_class = 255` (slave-only)

### PipeWire Configuration

Location: `/etc/pipewire/pipewire.conf.d/90-dante-bridge.conf`

Key settings:
- Sample rate: 96000 Hz (forced)
- Quantum: 512 samples (5.33ms latency)
- Resample quality: 10 (high quality)
- Adaptive resampling: enabled

## Services

### statime.service
- PTP daemon for Dante clock synchronization
- Must run before dante-bridge
- Syncs system clock to Dante PTPv1

### dante-bridge.service
- Main audio bridge service
- Depends on: statime, pipewire, wireplumber
- Manages audio routing and monitoring

### pipewire.service
- Audio server providing adaptive resampling
- Handles clock drift between Dante and USB domains
- Manages audio pipeline

## Operation

### Starting the Bridge

```bash
# Services start automatically on boot if enabled
# Manual start:
systemctl start statime
systemctl start pipewire
systemctl start dante-bridge
```

### Monitoring

```bash
# Check status
ndi-bridge-dante-status

# View logs
ndi-bridge-dante-logs

# Follow logs in real-time
ndi-bridge-dante-logs -f
```

### Audio Flow

1. Dante audio arrives via network (port 4321)
2. Inferno ALSA plugin receives audio at 96kHz
3. PipeWire creates ALSA loopback nodes
4. Adaptive resampling compensates for clock drift
5. Audio output to USB interface (Arturia/Focusrite)

## Network Requirements

### Required Ports

- **8700** - mDNS/Discovery
- **8800** - Control/Configuration  
- **8900** - Audio Routing
- **4321** - Audio Data
- **319-320** - PTP (UDP)

### Network Configuration

- Multicast must be enabled on interface
- Bridge interface (br0) used by default
- Device visible in Dante Controller as hostname

## Troubleshooting

### Device Not Visible in Dante Controller

1. Check discovery ports:
```bash
netstat -tuln | grep -E "8700|8800"
```

2. Verify Inferno is using correct ALSA config:
```bash
cat /root/.asoundrc
# Must show: type inferno (NOT type plug)
```

3. Check network interface:
```bash
ip link show br0 | grep MULTICAST
```

### Clock Sync Issues

1. Check PTP status:
```bash
ndi-bridge-dante-status
# Look for PTP offset and role
```

2. Verify ndi-bridge is follower:
```bash
journalctl -u statime | grep "becoming master"
# Should NOT see this message
```

3. Check for real Dante devices:
```bash
# If ndi-bridge becomes master, no other Dante devices detected
```

### Audio Dropouts/Xruns

1. Check xrun count:
```bash
ndi-bridge-dante-status
# Look for xruns count
```

2. Increase buffer size if needed:
```bash
# Edit /usr/local/bin/dante-bridge-production
# Increase QUANTUM value (default 512)
```

3. Check CPU usage:
```bash
top -p $(pgrep pipewire)
```

### USB Device Not Found

1. List USB audio devices:
```bash
aplay -l | grep USB
```

2. Check device permissions:
```bash
ls -la /dev/snd/
```

3. Verify device at 96kHz:
```bash
cat /proc/asound/card*/pcm*/sub0/hw_params
```

## Performance Tuning

### Latency Optimization

Default configuration provides ~15-25ms total latency:
- PipeWire quantum: 5.33ms (512 samples @ 96kHz)
- Adaptive resampling: ~10-15ms
- USB buffering: ~5ms

To reduce latency (may increase xruns):
1. Decrease quantum in dante-bridge-production
2. Reduce resampling quality in PipeWire config
3. Ensure real-time priorities are set

### CPU Optimization

- Inferno and Statime compiled with -O3 optimization
- PipeWire uses real-time scheduling (RT priority 85)
- Single-threaded design minimizes context switching

## Limitations

1. **PTP Version**: Dante uses PTPv1, incompatible with NDI's PTPv2
2. **Clock Master**: ndi-bridge cannot be Dante clock master
3. **Sample Rate**: Fixed at 96kHz for Dante compatibility
4. **Latency**: Minimum ~15ms due to adaptive resampling requirement
5. **Channels**: Currently stereo only (2 channels)

## Technical Details

### Why PipeWire?

Direct ALSA routing between Dante and USB fails due to clock drift. PipeWire provides:
- Adaptive resampling between clock domains
- Automatic drift compensation
- Professional-quality resampling algorithms
- Real-time safe operation

### Why Statime Fork?

Upstream Statime only supports PTPv2. The Inferno fork adds:
- PTPv1 support for Dante compatibility
- Proper multicast configuration
- Dante-specific timing parameters

### ALSA Configuration

Critical: Must use `type inferno` directly in ALSA config:
```
pcm.dante {
    type inferno  # NOT "type plug"!
    RX_CHANNELS 2
    TX_CHANNELS 2
    SAMPLE_RATE 96000
}
```

Using `type plug` prevents discovery ports from opening.

## Future Enhancements

Potential improvements for future versions:
- Multi-channel support (8/16/32 channels)
- Configurable sample rates (48kHz option)
- Dante Domain Manager integration
- Redundant network support
- AES67 compatibility mode