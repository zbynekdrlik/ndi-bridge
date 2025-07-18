# TODO

## Current Priority
- [x] Implement v2.1.0 extreme latency optimizations
- [x] Fix FPS issue in v2.1.1 (non-blocking poll)
- [ ] Test v2.1.1 with non-blocking poll implementation
- [ ] Measure FPS stability and latency reduction
- [ ] Verify 8 frame target latency achievement

## v2.1.1 Testing
- [ ] Verify 60 FPS stable (not 23-29)
- [ ] Verify 2 buffers active
- [ ] Verify RT priority 90
- [ ] Verify CPU affinity to core 3
- [ ] Verify non-blocking poll works correctly
- [ ] Measure actual round-trip latency in frames

## Performance Verification
- [ ] FPS should be solid 60
- [ ] Internal latency < 0.5ms
- [ ] Zero dropped frames
- [ ] Memory properly locked
- [ ] CPU usage high but stable on core 3

## If v2.1.1 Achieves 8 Frames
- [ ] Update PR #15 with success results
- [ ] Update CHANGELOG with v2.1.1 features
- [ ] Create release notes
- [ ] Merge to main
- [ ] Tag v2.1.1 release

## If v2.1.1 Still Issues (v2.2.0 ideas)
- [ ] Pure busy-wait without any poll
- [ ] Direct kernel bypass with custom module
- [ ] Implement V4L2_MEMORY_USERPTR for true zero-copy
- [ ] Use io_uring for async I/O
- [ ] Bypass V4L2 entirely - direct USB access
- [ ] Custom USB driver for HDMI capture
- [ ] Hardware DMA directly to NDI buffers

## Documentation
- [ ] Update README with v2.1.1 non-blocking poll
- [ ] Document FPS issue and resolution
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

## Known Issues
- [x] v2.1.0 with 1ms poll: FPS drops to 23-29
- [ ] v2.1.1 with non-blocking poll: Testing needed
