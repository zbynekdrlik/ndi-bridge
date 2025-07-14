# DeckLink Setup Guide

## Prerequisites

1. **Blackmagic Desktop Video**
   - Download from: https://www.blackmagicdesign.com/support/
   - Install Desktop Video driver
   - Reboot after installation

2. **DeckLink SDK**
   - Download from: https://www.blackmagicdesign.com/developer/
   - Extract to: `C:\Blackmagic DeckLink SDK 12.5\` (or your preferred location)
   - Set environment variable: `DECKLINK_SDK_DIR` to SDK path

## Building with DeckLink Support

```bash
# Enable DeckLink support
cmake -DUSE_DECKLINK=ON ..

# Or set SDK path explicitly
cmake -DUSE_DECKLINK=ON -DECKLINK_SDK_DIR="C:/Blackmagic DeckLink SDK 12.5" ..
```

## Supported DeckLink Devices

- DeckLink Mini Monitor
- DeckLink Mini Recorder
- DeckLink SDI
- DeckLink Studio
- DeckLink Duo
- DeckLink Quad
- UltraStudio devices

## Usage Examples

### List all devices (including DeckLink)
```bash
ndi-bridge.exe --list-devices
```

Output:
```
Media Foundation Devices:
  0: Integrated Camera
  1: USB Capture Device

DeckLink Devices:
  0: DeckLink Mini Recorder
  1: DeckLink SDI 4K
```

### Use specific DeckLink device
```bash
# By name
ndi-bridge.exe --capture-type decklink -d "DeckLink Mini Recorder"

# Interactive selection
ndi-bridge.exe --capture-type decklink
```

### DeckLink-specific options
```bash
# Set video format
ndi-bridge.exe --capture-type decklink --decklink-format "1080p30"

# Available formats:
# - 1080p30, 1080p25, 1080p24
# - 1080i60, 1080i50
# - 720p60, 720p50
# - 2160p30, 2160p25, 2160p24
```

## Troubleshooting

### DeckLink not detected
1. Check Desktop Video is installed
2. Run Blackmagic Desktop Video Setup
3. Verify device appears in Device Manager
4. Check PCIe connection (for internal cards)

### No video signal
1. Check SDI/HDMI cable connection
2. Verify input format matches source
3. Use Desktop Video Setup to test input
4. Try different video format with `--decklink-format`

### Build errors
1. Verify DECKLINK_SDK_DIR is set correctly
2. Check SDK version compatibility (12.0+)
3. Ensure Visual Studio has Windows SDK installed
