# NDI Bridge Design Philosophy

## Core Mission
**NDI Bridge is a specialized, high-performance, low-latency capture-to-NDI application.**

## Design Principles

### 1. Low Latency is NON-NEGOTIABLE
- Every design decision prioritizes latency reduction
- No "compatibility modes" that compromise latency
- If a feature adds latency, it doesn't belong here

### 2. Modern Hardware Only
- Target: Intel N100 and newer architectures
- Assume AVX2 support (2013+ CPUs)
- Assume sufficient RAM for pre-allocation
- Assume PCIe bandwidth for zero-copy operations

### 3. Simplicity Through Specialization
- ONE purpose: Get video from capture to NDI with minimal latency
- NO unnecessary options or flags
- NO "safe mode" fallbacks that add latency
- Always use the fastest path available

### 4. Zero-Copy by Default
- If the capture format is NDI-compatible (UYVY, BGRA), send it directly
- NEVER convert formats unless absolutely necessary
- Pre-allocate all buffers
- Direct callbacks only - no queuing

### 5. Performance Assumptions
- Users have modern, capable hardware
- Users prioritize latency over compatibility
- Users need professional-grade performance

## Implementation Guidelines

### Always:
- Use zero-copy paths when format is compatible
- Use SIMD (AVX2) for any required conversions
- Pre-allocate all buffers
- Use direct callbacks
- Minimize thread synchronization
- Use lock-free data structures where possible

### Never:
- Add "compatibility" options that increase latency
- Use queues when direct paths are possible
- Allocate memory during capture
- Add abstraction layers that increase overhead
- Compromise on performance for "safety"

## Target Performance
- Glass-to-glass latency: < 1 frame
- CPU usage: Minimal (offload to hardware where possible)
- Memory bandwidth: Optimize for zero-copy
- Format conversion: Only when absolutely necessary, always SIMD-optimized

## Remember
This is not a general-purpose tool. Users choosing NDI Bridge are choosing performance over flexibility. Every line of code should reflect this priority.

**When in doubt, choose speed.**
