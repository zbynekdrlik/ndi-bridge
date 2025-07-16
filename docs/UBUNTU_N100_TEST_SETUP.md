# Ubuntu N100 Test Environment Setup

## System Configuration
- **Hardware**: Intel N100 PC with AVX2 support
- **OS**: Ubuntu 24.04 LTS Live USB (via Ventoy)
- **Capture Card**: NZXT Signal HD60 (USB, /dev/video0)
- **Network**: 10.77.9.183 (SSH accessible)

## Current Directory Structure
```
/home/ubuntu/ndi-test/
├── Install_NDI_SDK_v6_Linux.sh
├── Install_NDI_SDK_v6_Linux.tar.gz
├── NDI SDK for Linux/          # NDI SDK installation
│   ├── include/
│   ├── lib/
│   └── examples/
└── ndi-bridge/                 # Git repository
    ├── build/                  # Build directory
    │   ├── CMakeCache.txt
    │   ├── CMakeFiles/
    │   ├── Makefile
    │   └── bin/
    │       └── ndi-bridge      # Executable v1.3.6
    └── src/                    # Source files
```

## Environment Setup Commands

### 1. Boot Ubuntu Live USB
```bash
# Using Ventoy USB with Ubuntu 24.04 ISO
# Boot from USB, select Ubuntu
```

### 2. Enable SSH Access
```bash
# On Ubuntu machine (one-time setup)
sudo apt update
sudo apt install -y openssh-server
sudo passwd ubuntu  # Set password (e.g., test123)
ip addr | grep inet  # Get IP address
```

### 3. Connect via SSH
```bash
# From main PC
ssh ubuntu@10.77.9.183
```

### 4. Install Build Dependencies
```bash
sudo apt update
sudo apt install -y build-essential cmake git wget v4l-utils
```

### 5. Setup NDI SDK
```bash
mkdir ~/ndi-test && cd ~/ndi-test

# Download NDI SDK (get current link from https://ndi.video/for-developers/ndi-sdk/)
wget https://downloads.ndi.tv/SDK/NDI_SDK_Linux/Install_NDI_SDK_v6_Linux.tar.gz
tar -xzf Install_NDI_SDK_v6_Linux.tar.gz
./Install_NDI_SDK_v6_Linux.sh

# SDK installs to ~/ndi-test/NDI SDK for Linux/
```

### 6. Clone and Build NDI Bridge
```bash
cd ~/ndi-test
git clone https://github.com/zbynekdrlik/ndi-bridge.git
cd ndi-bridge
git checkout feature/linux-usb-capture-support

# Set NDI SDK path
export NDI_SDK_DIR="$HOME/ndi-test/NDI SDK for Linux"

# Build
mkdir build && cd build
cmake ..
make -j$(nproc)
```

## Device Information

### USB Capture Card
```bash
$ v4l2-ctl --list-devices
NZXT Signal HD60 Video: NZXT Si (usb-0000:00:14.0-2):
        /dev/video0
        /dev/video1
        /dev/media0

$ v4l2-ctl --device=/dev/video0 --list-formats-ext
ioctl: VIDIOC_ENUM_FMT
        Type: Video Capture
        [0]: 'NV12' (Y/UV 4:2:0)
                Size: Discrete 1920x1080
                        Interval: Discrete 0.017s (60.000 fps)
                        Interval: Discrete 0.020s (50.000 fps)
                        Interval: Discrete 0.033s (30.000 fps)
                        Interval: Discrete 0.040s (25.000 fps)
        [1]: 'YUYV' (YUYV 4:2:2)
                Size: Discrete 1920x1080
                        Interval: Discrete 0.017s (60.000 fps)
                        # ... more formats
```

### CPU Information
```bash
$ cat /proc/cpuinfo | grep "model name" | head -1
model name      : Intel(R) N100

$ cat /proc/cpuinfo | grep flags | head -1 | grep -o avx2
avx2  # Confirms AVX2 support
```

## Testing Status (as of 2025-07-16)

### Version 1.3.5 Issues
- ✅ Compilation successful
- ✅ Device detection working
- ✅ NDI streaming established (2 connections)
- ❌ Black video output (YUV conversion bug)
- ✅ Low latency (~16ms)

### Version 1.3.6 Fix Applied
- Fixed AVX2 YUV-to-RGB conversion (coefficients scaled by 256)
- Awaiting test results
- Expected: Actual video output instead of black

## Test Commands

### List Devices
```bash
cd ~/ndi-test/ndi-bridge/build/bin
sudo ./ndi-bridge --list-devices
```

### Run NDI Bridge
```bash
sudo ./ndi-bridge --device /dev/video0 --ndi-name "NZXT HD60"
```

### Monitor Performance
```bash
# In another SSH session
htop  # Check CPU usage (should be <10%)
```

### Check Version
```bash
./ndi-bridge --version
# Should show: Version 1.3.6 loaded
```

## Known Issues & Solutions

### 1. NDI SDK Path
If cmake fails to find NDI SDK:
```bash
export NDI_SDK_DIR="$HOME/ndi-test/NDI SDK for Linux"
# or
export NDI_SDK_DIR="/home/ubuntu/ndi-test/NDI SDK for Linux"
```

### 2. V4L2 Buffer Warnings
ffmpeg shows "Dequeued v4l2 buffer contains corrupted data (0 bytes)"
- This is normal for some USB capture cards
- The NDI Bridge handles this correctly

### 3. Persistence
This is a Live USB without persistence, so:
- All changes are lost on reboot
- Need to reinstall everything each boot
- Consider setting up Ventoy persistence for permanent storage

## Network Testing
To verify NDI stream from another computer:
- Use NDI Studio Monitor or OBS with NDI plugin
- Look for source named "NZXT HD60" or configured name
- Should see video feed at 1920x1080 60fps

## Debug Information
If issues occur, collect:
```bash
# System info
uname -a
lsb_release -a

# USB info
lsusb | grep -i nzxt

# V4L2 details
v4l2-ctl --device=/dev/video0 --all

# Build logs
cd ~/ndi-test/ndi-bridge/build
make clean && make VERBOSE=1 2>&1 | tee build.log

# Runtime logs
sudo ./bin/ndi-bridge --device /dev/video0 --ndi-name "Test" --verbose 2>&1 | tee runtime.log
```

## Thread Continuity
For continuing work in a new thread:
1. Check this file for environment setup
2. Read THREAD_PROGRESS.md for development status
3. Current branch: `feature/linux-usb-capture-support`
4. Current version: 1.3.6
5. Main issue resolved: AVX2 black video (needs testing)
