# Building Media Bridge

This guide covers building Media Bridge from source on various platforms.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Build](#quick-build)
- [Linux Build Instructions](#linux-build-instructions)
- [Build Options](#build-options)
- [Troubleshooting](#troubleshooting)
- [USB Appliance Build](#usb-appliance-build)

## Prerequisites

### All Platforms
- CMake 3.16 or newer
- Git
- [NDI SDK](https://ndi.tv/sdk/) (5.0+ recommended, NDI 6 supported)

### Linux Requirements
- GCC 9+ or Clang 10+
- V4L2 development headers
- Build essentials

## Quick Build

### Clone and Build
```bash
# Clone repository
git clone https://github.com/zbynekdrlik/media-bridge.git
cd media-bridge

# Create build directory
mkdir build && cd build

# Configure
cmake -DCMAKE_BUILD_TYPE=Release ..

# Build
make -j$(nproc)
```

## Linux Build Instructions

#### 1. Install Prerequisites

Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    libv4l-dev \
    pkg-config
```

Fedora/RHEL:
```bash
sudo dnf install -y \
    gcc-c++ \
    cmake \
    git \
    v4l-utils-devel \
    pkgconfig
```

#### 2. Install NDI SDK
```bash
# Download NDI SDK for Linux
wget https://downloads.ndi.tv/SDK/NDI_SDK_Linux/Install_NDI_SDK_v5_Linux.tar.gz

# Extract and install
tar -xf Install_NDI_SDK_v5_Linux.tar.gz
sudo ./Install_NDI_SDK_v5_Linux.sh

# SDK installs to /usr/local/lib and /usr/local/include
```

#### 3. Build
```bash
# Configure with optimizations
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_FLAGS="-O3 -march=native" \
      ..

# Build with all cores
make -j$(nproc)

# Install (optional)
sudo make install
```

The executable will be in `build/ndi-capture`

## Build Options

### CMake Options
| Option | Description | Default |
|--------|-------------|---------|
| `CMAKE_BUILD_TYPE` | Build type (Debug/Release/RelWithDebInfo) | Release |
| `BUILD_TESTS` | Build unit tests | OFF |
| `NDI_SDK_DIR` | Custom NDI SDK location | AUTO |

### Example with Options
```bash
cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DBUILD_TESTS=ON \
      -DNDI_SDK_DIR=/custom/ndi/path \
      ..
```

### Optimization Flags

For maximum performance on Linux:
```bash
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_FLAGS="-O3 -march=native -mtune=native -ffast-math" \
      ..
```

For Intel N100 specifically:
```bash
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_FLAGS="-O3 -march=alderlake -mtune=alderlake" \
      ..
```

## Troubleshooting

### NDI SDK Not Found
```
CMake Error: Could not find NDI SDK
```

**Solution:**
- Run the official installer or set `NDI_SDK_DIR`
- Manual: `-DNDI_SDK_DIR=/path/to/ndi/sdk`

### V4L2 Headers Missing (Linux)
```
fatal error: linux/videodev2.h: No such file or directory
```

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get install libv4l-dev

# Fedora
sudo dnf install v4l-utils-devel
```

### Permission Denied (Linux)
```
/dev/video0: Permission denied
```

**Solution:**
```bash
# Add user to video group
sudo usermod -a -G video $USER

# Logout and login for changes to take effect
```

### Build Errors with AVX2
```
error: AVX2 instructions not supported
```

**Solution:**
Remove AVX2 flags if CPU doesn't support them:
```bash
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_FLAGS="-O2" \
      ..
```

## Testing the Build

After building, test with:
```bash
# List available devices
./ndi-capture --list

# Test with first device
./ndi-capture

# Test with specific device
./ndi-capture /dev/video0
```

## Creating a Release Build

For distribution:
```bash
# Linux
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_CXX_FLAGS="-O3 -march=x86-64 -mtune=generic" \
      ..
make -j$(nproc)
strip ndi-capture  # Remove debug symbols

# Windows
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build . --config Release
# Use Release/ndi-capture.exe
```

## USB Appliance Build

To create a bootable USB appliance that runs Media Bridge automatically:

```bash
# Build the binary first
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
cd ..

# Create bootable USB (requires root, with automatic logging)
sudo ./build-usb-with-log.sh /dev/sdX  # Replace sdX with your USB device
```

For detailed USB build instructions, see [USB Build Guide](docs/USB-BUILD.md).

## Next Steps

- For USB appliance details, see [USB Build Guide](docs/USB-BUILD.md)
- For usage instructions, see [README.md](README.md)
- For development, see [CONTRIBUTING.md](CONTRIBUTING.md)