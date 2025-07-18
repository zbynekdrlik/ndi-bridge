# TODO

## Current Priority
- [x] Implement v2.1.0 extreme latency optimizations
- [ ] Test v2.1.0 with FIXED implementation
- [ ] Measure latency reduction with proper 2 buffers + busy-wait
- [ ] Verify 8 frame target latency achievement

## v2.1.0 Testing
- [ ] Verify 2 buffers active (not 3)
- [ ] Verify RT priority 90 (not 80)
- [ ] Verify CPU affinity to core 3
- [ ] Verify busy-wait (100% CPU usage)
- [ ] Measure actual round-trip latency in frames

## Performance Verification
- [ ] FPS should be solid 60
- [ ] Internal latency < 0.5ms
- [ ] Zero dropped frames
- [ ] Memory properly locked

## If v2.1.0 Achieves 8 Frames
- [ ] Update PR #15 with success results
- [ ] Update CHANGELOG with v2.1.0 features
- [ ] Create release notes
- [ ] Merge to main
- [ ] Tag v2.1.0 release

## If v2.1.0 Still >8 Frames (v2.2.0 ideas)
- [ ] Direct kernel bypass with custom module
- [ ] Implement V4L2_MEMORY_USERPTR for true zero-copy
- [ ] Use io_uring for async I/O
- [ ] Bypass V4L2 entirely - direct USB access
- [ ] Custom USB driver for HDMI capture
- [ ] Hardware DMA directly to NDI buffers

## Documentation
- [ ] Update README with v2.1.0 extreme mode
- [ ] Document latency measurement methodology
- [ ] Create Linux performance tuning guide
- [ ] Add troubleshooting for capabilities
- [ ] Document CPU affinity impact

## Future Optimizations
- [ ] Multi-queue support for parallel processing
- [ ] GPU acceleration for format conversion
- [ ] Kernel bypass networking for NDI
- [ ] Custom real-time kernel patches
- [ ] Hardware timestamping support

## Benchmarking
- [ ] Create automated latency test suite
- [ ] Compare with commercial solutions
- [ ] Profile CPU usage patterns
- [ ] Measure power consumption impact
