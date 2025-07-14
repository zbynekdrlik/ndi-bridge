# DeckLink SDK Setup Instructions

## Important Legal Notice
The DeckLink SDK files are proprietary files owned by Blackmagic Design and cannot be redistributed in this repository due to licensing restrictions.

## Obtaining the DeckLink SDK

1. **Download the SDK**:
   - Visit [Blackmagic Design Support](https://www.blackmagicdesign.com/support/)
   - Navigate to "Latest Downloads"
   - Find "Desktop Video Developer SDK" (currently version 14.4 or later)
   - Download for your platform (Windows/Linux/macOS)
   - You may need to create a free account

2. **Extract the SDK**:
   - Windows: Extract the ZIP file
   - The SDK contains IDL files that need to be compiled

## Generating Required Files from IDL

The DeckLink SDK provides IDL (Interface Definition Language) files that must be compiled to generate the C++ headers and source files.

### Method 1: Using the provided script (Recommended)

1. **Open Visual Studio Developer Command Prompt** (not regular cmd):
   - Start Menu → Visual Studio 2019/2022 → Developer Command Prompt

2. **Navigate to the SDK include directory**:
   ```cmd
   cd "path\to\Blackmagic DeckLink SDK 14.4\Win\include"
   ```

3. **Copy and run our generation script**:
   ```cmd
   copy path\to\ndi-bridge\scripts\generate-decklink-api.bat .
   generate-decklink-api.bat
   ```

4. **Copy generated files to the project**:
   ```cmd
   copy DeckLinkAPI_h.h path\to\ndi-bridge\docs\reference\
   copy DeckLinkAPI_i.c path\to\ndi-bridge\docs\reference\
   ```

### Method 2: Manual MIDL compilation

1. **Open Visual Studio Developer Command Prompt**

2. **Navigate to SDK include directory**:
   ```cmd
   cd "path\to\Blackmagic DeckLink SDK 14.4\Win\include"
   ```

3. **Run MIDL compiler**:
   ```cmd
   midl /h DeckLinkAPI_h.h /iid DeckLinkAPI_i.c DeckLinkAPI.idl
   ```

4. **Copy generated files** to `docs/reference/`:
   - `DeckLinkAPI_h.h` - Main header file
   - `DeckLinkAPI_i.c` - Interface IDs/GUIDs

## Verify Installation

After copying the files, verify CMake finds them:
```bash
mkdir build
cd build
cmake ..
```

You should see:
```
DeckLink SDK found: .../docs/reference
```

## Building Without DeckLink Support

If you don't need DeckLink support, you can disable it:
```bash
cmake -DUSE_DECKLINK=OFF ..
```

This will build NDI Bridge with only Media Foundation support (Windows) or V4L2 support (Linux, when implemented).

## Troubleshooting

### "midl.exe not found"
- Make sure you're using Visual Studio Developer Command Prompt, not regular Command Prompt
- MIDL is included with Visual Studio C++ development tools

### "DeckLink SDK not found" Warning
This is normal if you haven't added the SDK files yet. The build will continue without DeckLink support.

### MIDL Compilation Errors
- Ensure you're in the correct directory with all IDL files present
- Some warnings are normal during MIDL compilation

### License Compliance
- DO NOT commit the generated SDK files to any public repository
- DO NOT redistribute the SDK files with your binaries
- Users must obtain the SDK from Blackmagic Design directly
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

## Alternative: Pre-generated Files

If you have trouble generating the files, you might find pre-generated versions in:
- An existing Desktop Video installation
- Previous DeckLink SDK versions that included pre-compiled headers
- Other DeckLink projects (ensure license compatibility)

Note: Always prefer generating from the IDL files to ensure compatibility with your SDK version.
