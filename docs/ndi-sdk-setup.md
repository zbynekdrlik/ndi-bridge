# NDI SDK Setup Guide

This guide explains how to set up the NDI SDK for the NDI Bridge project.

## Prerequisites

- NDI SDK (download from https://ndi.video/for-developers/ndi-sdk/)
- You'll need to create a free account to download

## Setup Options

### Option 1: Local Project Directory (Recommended)

This approach keeps the NDI SDK with your project, making it portable.

1. Create the directory structure:
   ```
   ndi-bridge/
   └── deps/
       └── ndi/
           ├── include/
           └── lib/
               └── x64/
   ```

2. Copy NDI SDK files:
   - From NDI SDK `include/` → `deps/ndi/include/`
     - Must include `Processing.NDI.Lib.h`
   - From NDI SDK `lib/x64/` → `deps/ndi/lib/x64/`
     - `Processing.NDI.Lib.x64.lib`
     - `Processing.NDI.Lib.x64.dll`

### Option 2: System Installation

1. Download and install the NDI SDK
2. Default installation paths:
   - NDI 5: `C:\Program Files\NDI\NDI 5 SDK\`
   - NDI 6: `C:\Program Files\NDI\NDI 6 SDK\`
3. CMake will automatically find it in these locations

### Option 3: Custom Location with Environment Variable

1. Install/extract NDI SDK to any location
2. Set environment variable:
   ```cmd
   setx NDI_SDK_DIR "C:\path\to\your\ndi\sdk"
   ```
3. Restart Visual Studio or command prompt

## Verification

After setup, CMake should show:
```
NDI SDK found:
  Include: [path to includes]
  Library: [path to library]
```

## Troubleshooting

If CMake can't find NDI SDK:
1. Verify file paths are correct
2. Check that all required files are present
3. For Option 1, ensure files are in `deps/ndi/` relative to project root
4. For Option 3, verify environment variable is set (run `echo %NDI_SDK_DIR%`)

## Required Files Summary

| File | Purpose | Location |
|------|---------|----------|
| Processing.NDI.Lib.h | Header file | include/ |
| Processing.NDI.Lib.x64.lib | Import library | lib/x64/ |
| Processing.NDI.Lib.x64.dll | Runtime library | lib/x64/ |

## Next Steps

Once NDI SDK is configured:
1. Rebuild the project in Visual Studio
2. The build process will automatically copy the DLL to the output directory
3. Test with `ndi-bridge.exe --version`
