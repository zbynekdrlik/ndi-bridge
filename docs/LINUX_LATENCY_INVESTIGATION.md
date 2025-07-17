# Linux V4L2 Latency Investigation Plan

## Current Situation
- **Windows Media Foundation**: 8 frames latency (FIXED in v1.6.7)
- **Linux V4L2**: 12 frames latency (50% worse than Windows!)
- **Target**: Reduce Linux latency from 12 to 8 frames

## Key Learnings from Windows Fix

### 1. NDI Configuration
- **CRITICAL**: NDI clock_video=false for immediate delivery
- When true, NDI paces frames causing 3-5 frame delay
- Check: Does Linux implementation set this correctly?

### 2. Capture Loop Design
- **NO SLEEPS**: Reference implementation uses tight loops
- Even 5ms sleep adds significant latency
- Check: Are there any sleeps in V4L2 capture loops?

### 3. Threading Model Impact
- Windows single capture thread: 8 frames
- Linux 3-thread pipeline: 12 frames
- Threading adds synchronization overhead
- Consider: Is multi-threading worth the latency cost?

### 4. Buffering and Queues
- Every queue/buffer adds latency
- Frame queues between threads are suspect
- Check: Queue depths and buffer counts

## Investigation Steps

### Step 1: NDI Sender Analysis
```cpp
// Check in ndi_sender.cpp for Linux
// Look for clock_video setting
NDI_send_create_desc.clock_video = ???  // Should be false!
```

### Step 2: V4L2 Capture Loop
```cpp
// Check v4l2_capture.cpp and v4l2_capture_multi.cpp
// Look for any sleep/usleep/nanosleep calls
// Look for blocking operations that could add delay
```

### Step 3: Multi-Threading Analysis
Current v1.5.0 architecture:
- Thread 1: V4L2 capture
- Thread 2: Format conversion  
- Thread 3: NDI send
- Frame queues between each thread

Each queue adds buffering delay!

### Step 4: V4L2 Buffer Configuration
```cpp
// Check buffer request count
req.count = ???  // Currently 10, might be too high
req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
req.memory = V4L2_MEMORY_MMAP;
```

### Step 5: Frame Queue Depths
```cpp
// Check FrameQueue capacity
FrameQueue queue(capacity);  // What's the capacity?
```

## Proposed Solutions

### Option 1: Quick Fixes (Try First)
1. Set NDI clock_video=false
2. Remove any sleeps in capture loops
3. Reduce V4L2 buffer count (10 → 4)
4. Reduce frame queue sizes (minimize buffering)

### Option 2: Single-Thread Mode
1. Add a single-threaded capture option
2. Similar to Windows: Capture → Convert → Send in one thread
3. Eliminate inter-thread queues
4. Keep multi-thread as option for CPU-limited systems

### Option 3: Hybrid Approach
1. Merge capture + convert into one thread
2. Keep NDI send separate (it can block)
3. Single queue instead of two
4. Reduces thread overhead while maintaining some parallelism

## Implementation Priority

1. **First**: Check and fix NDI clock_video setting
2. **Second**: Remove any sleeps/delays in capture
3. **Third**: Reduce buffer counts and queue sizes
4. **Fourth**: If still > 8 frames, implement single-thread option
5. **Fifth**: Profile and optimize remaining bottlenecks

## Success Metrics

- Primary: Achieve 8 frames latency (matching Windows)
- Secondary: Maintain 60 FPS capture rate
- Bonus: Keep CPU usage reasonable (< 20% on Intel N100)

## Testing Methodology

1. Use same 60fps camera as Windows testing
2. Measure round-trip latency with same method
3. Compare directly with Windows results
4. Test both single and multi-threaded modes
5. Profile CPU usage for each configuration

## Expected Outcomes

- Quick fixes alone might reduce 12 → 9-10 frames
- Single-thread mode should achieve 8 frames
- Multi-thread can remain as option for specific use cases
- Linux should match or beat Windows performance
