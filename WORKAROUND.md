# Workaround for Low FPS Issue

## Problem
The NZXT HD60 (and possibly other HDMI capture devices) cannot deliver 1920x1080 YUYV at 60fps over USB, resulting in:
- Only 26 FPS instead of 60 FPS
- High latency due to irregular frame delivery
- Frame gaps of 25-48ms instead of 16.67ms

## Root Cause
USB bandwidth limitation for uncompressed 1080p60 YUYV format:
- 1920x1080 YUYV at 60fps = ~237 MB/s
- Many USB capture devices can't sustain this bandwidth

## Workaround Solutions

### 1. Use 720p60 (Recommended)
```bash
# Run the provided script:
./run-720p60.sh

# Or manually:
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1280,height=720,pixelformat=YUYV
./ndi-bridge /dev/video0 "NZXT HD60"
```
**Benefits**: 
- Achieves true 60fps
- Lower latency (closer to 8 frames target)
- Still good quality for most use cases

### 2. Use NV12 Format
```bash
v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=NV12
./ndi-bridge /dev/video0 "NZXT HD60"
```
**Note**: Requires format conversion, slight CPU overhead

### 3. Check USB Connection
- Ensure device is connected to USB 3.0 port (blue port)
- Use `lsusb -t` to verify USB speed
- Try different USB ports

### 4. Alternative Devices
For true 1080p60 with low latency, consider:
- PCIe capture cards (no USB bottleneck)
- Professional USB 3.0 capture devices
- Devices with hardware compression

## Diagnostics
Run diagnostics to find best settings for your device:
```bash
./diagnose-capture.sh
```

## Expected Results with 720p60
- 60 FPS capture rate
- ~16.67ms frame intervals
- Target: 8 frames latency (133ms)
- Smooth, consistent frame delivery
