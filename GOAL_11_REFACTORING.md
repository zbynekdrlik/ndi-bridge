# GOAL 11: Refactor DeckLinkCaptureDevice.cpp

## Target for Next Thread

### Analysis Complete

The `src/capture/DeckLinkCaptureDevice.cpp` file is currently 677 lines and handles multiple responsibilities:

1. **CaptureCallback Class** (~50 lines)
2. **Device Initialization** (~90 lines)
3. **Capture Control** (~60 lines)
4. **Frame Processing** (~110 lines)
5. **Format Management** (~70 lines)
6. **Frame Conversion** (~70 lines)
7. **Statistics Tracking** (~70 lines)
8. **Utility Functions** (~50 lines)

### Proposed Refactoring

#### 1. **DeckLinkCaptureCallback.h/cpp**
- Extract the `CaptureCallback` class
- Handle IDeckLinkInputCallback implementation
- ~50 lines

#### 2. **DeckLinkFrameQueue.h/cpp**
- Frame queue management
- Thread-safe queue operations
- Frame dropping logic
- ~80 lines

#### 3. **DeckLinkStatistics.h/cpp**
- FPS calculation (rolling average)
- Frame counting
- Statistics logging
- ~70 lines

#### 4. **DeckLinkFormatManager.h/cpp**
- Format detection
- Format change handling
- Display mode management
- ~70 lines

#### 5. **DeckLinkDeviceInitializer.h/cpp**
- Device discovery
- Serial number retrieval
- Interface setup
- ~90 lines

### Benefits

1. **Single Responsibility Principle** - Each class has one clear purpose
2. **Easier Testing** - Can unit test individual components
3. **Better Maintainability** - Smaller files are easier to understand
4. **Faster Compilation** - Changes don't require recompiling everything
5. **Clearer Architecture** - Obvious where to find specific functionality

### Implementation Plan

1. Create new header/cpp files for each component
2. Extract relevant code with minimal changes
3. Update DeckLinkCaptureDevice to use new components
4. Ensure all functionality remains intact
5. Update CMakeLists.txt with new files
6. Test thoroughly

### Estimated Work

- Time: 2-3 hours
- Risk: Low (refactoring only, no functionality changes)
- Version: Would become v1.2.0 (minor version bump for internal refactoring)
