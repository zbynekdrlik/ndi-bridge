# DeckLink Setup Guide

## Prerequisites

1. **Blackmagic Desktop Video**
   - Download from: https://www.blackmagicdesign.com/support/
   - Install Desktop Video driver
   - Reboot after installation

2. **DeckLink SDK**
   - Download from: https://www.blackmagicdesign.com/developer/
   - Extract to: `C:\Blackmagic DeckLink SDK 12.5\` (or your preferred location)
   - Copy IDL files to `docs/reference/` and generate API files
   - See [DeckLink SDK Setup](decklink-sdk-setup.md) for detailed instructions

## Building with DeckLink Support

```bash
# Enable DeckLink support (default is ON)
cmake -DUSE_DECKLINK=ON ..

# Or disable if needed
cmake -DUSE_DECKLINK=OFF ..
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

### List all devices
```bash
# List Media Foundation devices
ndi-capture.exe -t mf -l

# List DeckLink devices
ndi-capture.exe -t dl -l
```

Output:
```
[DeckLink] Found device [0]: "DeckLink Mini Recorder" (Serial: 12345678)
[DeckLink] Found device [1]: "DeckLink SDI 4K"
```

### Use specific DeckLink device
```bash
# By name
ndi-capture.exe -t dl -d "DeckLink Mini Recorder" -n "SDI Stream"

# Interactive selection
ndi-capture.exe -t dl
```

### DeckLink Features
- **Automatic format detection**: Detects input format automatically
- **No-signal handling**: Gracefully handles signal loss
- **Serial number tracking**: Persists device selection across reconnects
- **Rolling FPS calculation**: Monitors capture performance
- **Format support**: UYVY and BGRA formats

## Troubleshooting

### DeckLink not detected
1. Check Desktop Video is installed
2. Run Blackmagic Desktop Video Setup
3. Verify device appears in Device Manager
4. Check PCIe connection (for internal cards)
5. Ensure DeckLink API files exist in `docs/reference/`

### No video signal
1. Check SDI/HDMI cable connection
2. Verify input format matches source
3. Use Desktop Video Setup to test input
4. Check application logs for "No input signal" messages

### Build errors
1. Verify DeckLink API files are generated:
   - `docs/reference/DeckLinkAPI_h.h`
   - `docs/reference/DeckLinkAPI_i.c`
2. Run generation script if needed:
   ```cmd
   cd docs\reference
   generate-decklink-api.bat
   ```
3. Ensure Visual Studio has Windows SDK installed

### Runtime errors
1. Check if Desktop Video drivers are installed
2. Verify no other application is using the DeckLink device
3. Try running as Administrator
4. Check Windows Event Log for driver issues
