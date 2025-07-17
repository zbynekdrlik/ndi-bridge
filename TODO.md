# NDI Bridge - TODO List

This file tracks future improvements and feature ideas for the NDI Bridge project.

## 🐛 Known Issues

### Connection Count Bug
- [ ] NDI connection count shows 2 when only 1 client connected
  - Might be double-counting the same connection
  - Could be a stale connection not cleaned up
  - Need to investigate NDI SDK connection tracking

## 🚀 Performance Optimizations

### Multi-threaded Pipeline
- [ ] Implement V4L2-style 3-thread model for DeckLink
  - Capture thread (highest priority)
  - Processing thread
  - NDI send thread
  - Could further reduce latency

### Hardware Acceleration
- [ ] Investigate GPU color conversion for non-native formats
- [ ] Direct DMA access if possible with DeckLink SDK
- [ ] Hardware timestamp support

### AVX2 Optimizations
- [ ] Implement AVX2 SIMD for remaining format conversions
  - YUV420 to BGRA
  - RGB to BGRA
  - Other rare formats

## ✨ Features

### Configuration
- [ ] Add configuration file support (JSON/YAML)
- [ ] Save last used settings
- [ ] Per-device configuration profiles

### Network Discovery
- [ ] Implement mDNS/Bonjour for automatic NDI discovery
- [ ] Web UI for remote configuration
- [ ] REST API for monitoring and control

### Additional Capture Support
- [ ] Screen capture support
- [ ] Virtual camera input
- [ ] DirectShow capture (Windows)
- [ ] AVFoundation capture (macOS)

### NDI Features
- [ ] NDI HX support for bandwidth-limited networks
- [ ] NDI recording capability
- [ ] NDI tally light support
- [ ] NDI PTZ camera control passthrough

### Monitoring
- [ ] Prometheus metrics export
- [ ] Real-time latency measurement
- [ ] Frame drop alerting
- [ ] Network bandwidth monitoring

## 📚 Documentation

- [ ] Create video tutorial for setup
- [ ] Benchmark results documentation
- [ ] Troubleshooting guide
- [ ] API documentation (if REST API added)

## 🔧 Code Quality

### Code Consolidation (HIGH PRIORITY)
- [ ] **Consolidate capture implementations into unified low-latency architecture**
  - Media Foundation, DeckLink, and Linux V4L2 have duplicate code
  - Create common base classes with platform-specific implementations
  - Share zero-copy logic, frame callbacks, and buffer management
  - Maintain extreme low-latency optimizations across all platforms
  - Benefits:
    - Reduce code duplication
    - Easier maintenance
    - Consistent performance across platforms
    - Single place to optimize
  - Key areas to consolidate:
    - Frame callback mechanisms
    - Buffer pre-allocation strategies
    - Zero-copy paths
    - Statistics and performance tracking
    - Format conversion pipelines

### Testing & CI
- [ ] Add unit tests for critical components
- [ ] Set up CI/CD pipeline
- [ ] Code coverage reporting
- [ ] Static analysis integration

## 🎯 Long-term Goals

- [ ] Sub-frame latency measurement tools
- [ ] Professional broadcast features
- [ ] Cloud deployment support
- [ ] Mobile app for monitoring

## 📝 Notes

- Priority should always be on maintaining low latency
- Any new feature must not compromise the core performance
- Follow the design philosophy in `docs/DESIGN_PHILOSOPHY.md`
