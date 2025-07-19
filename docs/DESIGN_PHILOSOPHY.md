# NDI Bridge Design Philosophy

## Core Mission
**NDI Bridge is a SINGLE-PURPOSE, ZERO-COMPROMISE, ultra-low-latency capture-to-NDI appliance.**

## Fundamental Truth
**This is NOT a general-purpose application. This is a dedicated appliance that does ONE thing: capture to NDI at ABSOLUTE MINIMUM LATENCY.**

## Design Principles

### 1. ZERO COMPROMISE
- **NO OPTIONS** - The application runs ONE way: the FASTEST way
- **NO MODES** - There is no "compatibility mode" or "safe mode"
- **NO FALLBACKS** - If the optimal path fails, the application fails
- **NO CONFIGURATION** - The code IS the configuration
- Every single decision is hardcoded for maximum performance

### 2. Low Latency is THE ONLY PRIORITY
- Target: 2-3 frames glass-to-glass latency
- If a feature adds even 1ms of latency, it doesn't exist
- Performance is not "a" priority, it is THE ONLY priority
- We measure success in microseconds saved

### 3. Single Hardware Target
- Built for: Intel N100 running dedicated Linux
- Assumes: AVX2, sufficient RAM, USB3/PCIe capture
- No compatibility with older hardware
- No Windows, no Mac, no ARM - just x86_64 Linux on N100

### 4. Simplicity Through Elimination
- ONE purpose: V4L2 capture → NDI output
- ONE configuration: Maximum performance
- ONE thread model: Whatever is fastest
- ONE buffer count: The minimum that works
- NO user choices - we've already made the optimal choice

### 5. Zero-Copy ALWAYS
- YUV formats (UYVY/YUYV) go directly to NDI
- NO intermediate buffers
- NO format conversion unless physically impossible
- Memory is allocated ONCE at startup

## Implementation Rules

### ALWAYS:
- Run with real-time scheduling (SCHED_FIFO)
- Use minimum buffer count (3)
- Zero-copy for YUV formats
- Single-threaded if it's faster
- Lock all memory (mlockall)
- Use immediate polling (0ms timeout)
- Apply every possible optimization

### NEVER:
- Add command-line options for performance tuning
- Create "modes" or "profiles"
- Make performance configurable
- Add safety checks that impact latency
- Compromise for compatibility
- Add features

## What This Means in Practice

```cpp
// WRONG - Too many options
if (low_latency_mode) {
    buffer_count = 4;
} else {
    buffer_count = 10;
}

// RIGHT - No options
constexpr int BUFFER_COUNT = 3;  // Minimum that works
```

```cpp
// WRONG - Configurable
void setMultiThreadingEnabled(bool enable);

// RIGHT - Hardcoded
constexpr bool USE_SINGLE_THREAD = true;  // Measured to be fastest
```

## Target Metrics
- Latency: 2-3 frames maximum (33-50ms at 60fps)
- CPU usage: < 10% on N100
- Memory bandwidth: Minimal (zero-copy)
- Configuration options: ZERO

## Usage
```bash
# This is the ONLY way to run it
ndi-bridge /dev/video0 "Stream Name"

# No --low-latency flag (always low latency)
# No --threads option (always optimal)
# No --buffers option (always minimum)
# No --mode option (always maximum performance)
```

## Remember
**We are building an APPLIANCE, not an application.**

Like a Formula 1 car:
- It does ONE thing: go fast
- It works ONE way: flat out
- It has ONE configuration: maximum performance
- If you want comfort options, buy a different car

**When in doubt, remember: SINGLE-PURPOSE, ZERO-COMPROMISE, ALWAYS MAXIMUM PERFORMANCE.**

## Version 2.0 Manifesto
Version 2.0 marks the transition from a configurable application to a dedicated performance appliance. All performance "options" are removed. The code now embodies a single, uncompromising configuration: the absolute fastest way to get video from V4L2 to NDI on Intel N100 hardware.

**This is the way.**
