# TODO

## Current Priority
- [ ] Implement v1.8.0 ultra-low latency code changes
- [ ] Test zero-copy YUV path with 60fps camera
- [ ] Measure latency reduction from direct YUYV support
- [ ] Verify 2-3 frame target latency achievement

## v1.8.0 Implementation
- [ ] Apply v4l2_capture.cpp modifications from artifact
- [ ] Apply main.cpp command-line option changes
- [ ] Compile and fix any build errors
- [ ] Test all performance modes

## Testing Matrix
- [ ] Normal mode (baseline)
- [ ] --zero-copy mode
- [ ] --single-thread mode
- [ ] --low-latency mode
- [ ] --ultra-low-latency mode
- [ ] --ultra-low-latency --realtime 80

## Future Optimizations (if needed)
- [ ] Implement full DMABUF support with buffer allocation
- [ ] Add V4L2_MEMORY_USERPTR support
- [ ] Investigate kernel bypass techniques
- [ ] Consider custom V4L2 driver for ultimate performance
- [ ] Add CPU affinity for capture thread
- [ ] Implement NUMA optimization

## Documentation
- [ ] Update README with new performance options
- [ ] Document latency measurement methodology
- [ ] Create performance tuning guide
- [ ] Add troubleshooting for real-time scheduling

## Release
- [ ] Create PR once target latency achieved
- [ ] Update CHANGELOG with v1.8.0 features
- [ ] Tag release after merge
