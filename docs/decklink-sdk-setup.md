# DeckLink SDK Setup Instructions

## Important Legal Notice
The DeckLink SDK files (`DeckLinkAPI_h.h` and `DeckLinkAPI_i.c`) are proprietary files owned by Blackmagic Design and cannot be redistributed in this repository due to licensing restrictions.

## Obtaining the DeckLink SDK

1. **Download the SDK**:
   - Visit [Blackmagic Design Support](https://www.blackmagicdesign.com/support/)
   - Navigate to "Latest Downloads"
   - Find "Desktop Video Developer SDK" (currently version 14.1 or later)
   - Download for your platform (Windows/Linux/macOS)
   - You may need to create a free account

2. **Extract the SDK**:
   - Windows: Extract the ZIP file
   - The SDK contains documentation, examples, and the required header files

3. **Locate Required Files**:
   - Windows: `Win/include/` directory in the SDK
   - Find these two files:
     - `DeckLinkAPI.h` (rename to `DeckLinkAPI_h.h`)
     - `DeckLinkAPI_i.c`

## Installation for NDI Bridge

1. **Create the directory** (if it doesn't exist):
   ```
   mkdir -p docs/reference
   ```

2. **Copy the files**:
   ```
   # From the DeckLink SDK Win/include directory:
   copy DeckLinkAPI.h docs/reference/DeckLinkAPI_h.h
   copy DeckLinkAPI_i.c docs/reference/DeckLinkAPI_i.c
   ```

   Note: We rename `DeckLinkAPI.h` to `DeckLinkAPI_h.h` to avoid conflicts with system headers.

3. **Verify CMake finds the SDK**:
   ```
   mkdir build
   cd build
   cmake ..
   ```
   
   You should see:
   ```
   DeckLink SDK found: .../docs/reference
   ```

## Alternative: System-wide Installation

If you have the Desktop Video software installed, you might already have the SDK headers:
- Windows: `C:\Program Files\Blackmagic Design\DeckLink SDK\Win\include\`
- Linux: `/usr/include/blackmagic/`

You can set the environment variable to point to the SDK:
```bash
# Windows
set DECKLINK_SDK_DIR=C:\Program Files\Blackmagic Design\DeckLink SDK\Win

# Linux
export DECKLINK_SDK_DIR=/usr/include/blackmagic
```

## Building Without DeckLink Support

If you don't need DeckLink support, you can disable it:
```bash
cmake -DUSE_DECKLINK=OFF ..
```

This will build NDI Bridge with only Media Foundation support (Windows) or V4L2 support (Linux, when implemented).

## Troubleshooting

### "DeckLink SDK not found" Warning
This is normal if you haven't added the SDK files yet. The build will continue without DeckLink support.

### Multiple SDK Versions
If you have multiple versions installed, CMake will use the first one it finds. To use a specific version:
1. Place the files in `docs/reference/` (highest priority)
2. Or set `DECKLINK_SDK_DIR` environment variable

### License Compliance
- DO NOT commit the DeckLink SDK files to any public repository
- DO NOT redistribute the SDK files with your binaries
- Users must obtain the SDK files from Blackmagic Design directly
- The SDK is free but requires acceptance of Blackmagic's license terms

## Runtime Requirements

Even with the SDK installed for building, users need:
1. **Desktop Video Drivers**: Download from Blackmagic Design support
2. **DeckLink Hardware**: Any Blackmagic capture card with input support
3. **Windows**: Visual C++ Redistributables (usually already installed)

## Testing DeckLink Support

After building with DeckLink support:
```bash
# List DeckLink devices
ndi-bridge.exe -t dl -l

# Use a specific DeckLink device
ndi-bridge.exe -t dl -d "DeckLink Mini Recorder" -n "My NDI Stream"
```
