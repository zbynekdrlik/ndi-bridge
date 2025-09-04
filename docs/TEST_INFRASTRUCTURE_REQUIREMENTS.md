# Test Infrastructure Requirements

## Overview
This document outlines the infrastructure and hardware requirements for complete test execution of the Media Bridge unified PipeWire architecture.

## Infrastructure-Dependent Test Failures

### 1. Display/Audio Tests
**Tests Affected**: 
- `test_display_stream_playback_with_audio`
- `test_display_pipewire_audio_display_1`
- `test_display_pipewire_audio_display_2`
- `test_display_audio_continuity`

**Requirements**:
- At least one connected HDMI display
- HDMI audio capability on the display
- Valid NDI stream source for playback tests

**Current Issue**: Test box (10.77.8.124) has no connected displays, causing these tests to skip or fail.

### 2. Intercom Tests
**Tests Affected**:
- `test_chrome_push_parameter_matches_hostname`
- `test_full_rename_flow`

**Requirements**:
- Chrome browser installed and running
- VDO.Ninja accessible
- USB audio device connected
- Stable network connection

**Current Issue**: Chrome startup can be slow, requiring increased timeouts (120s).

### 3. Performance Tests
**Tests Affected**:
- `test_no_memory_leaks_over_time`

**Requirements**:
- Stable system for 60+ seconds
- No other processes affecting memory
- Consistent capture workload

**Current Issue**: Requires 90s timeout for proper measurement.

### 4. Time Synchronization Tests
**Tests Affected**:
- `test_systemd_timesyncd_installed`
- `test_systemd_timesyncd_enabled`
- `test_systemd_timesyncd_running`

**Requirements**:
- Either systemd-timesyncd OR chrony installed
- NTP servers accessible

**Current Issue**: Box uses chrony instead of systemd-timesyncd. Tests updated to support both.

## Hardware Requirements for Full Testing

### Minimum Configuration
- Intel N100 or equivalent CPU
- 8GB RAM
- USB 3.0 capture device
- USB audio device (CSCTek or compatible)
- At least 1 HDMI output
- Gigabit Ethernet

### Recommended Configuration
- Intel N100 CPU
- 16GB RAM
- USB 3.0 capture device (Magewell or compatible)
- CSCTek USB audio device
- 3x HDMI outputs
- Connected HDMI displays with audio
- Gigabit Ethernet
- Access to NDI streams on network

## Network Requirements

### Essential Services
- DHCP server
- DNS resolution
- NTP server access
- mDNS/Avahi support

### For Complete Testing
- Multiple NDI stream sources
- VDO.Ninja access (vdo.ninja)
- Local network <10ms latency
- No firewall blocking:
  - NDI discovery (mDNS port 5353)
  - NDI streams (TCP 5960+)
  - VNC (port 5900)
  - HTTP (port 80)

## Test Environment Setup

### Pre-Test Checklist
1. **Hardware Connections**
   - [ ] USB capture device connected
   - [ ] USB audio device connected
   - [ ] At least one HDMI display connected
   - [ ] Ethernet cable connected

2. **Services Running**
   - [ ] PipeWire system service
   - [ ] WirePlumber system service
   - [ ] NDI capture service
   - [ ] Intercom service (if testing intercom)

3. **Network Verification**
   - [ ] Device has IP address
   - [ ] Can ping gateway
   - [ ] DNS resolution working
   - [ ] NTP synchronized

### Known Test Limitations

1. **Without HDMI Displays**
   - Display audio tests will skip
   - HDMI audio routing untestable
   - Console recovery tests limited

2. **Without USB Audio**
   - Intercom tests will fail
   - Virtual device routing untestable
   - Monitor loopback unavailable

3. **Without NDI Streams**
   - Playback tests use fallback streams
   - Stream switching tests limited
   - Audio sync tests unavailable

## Test Execution Strategies

### Quick Validation (No Hardware)
```bash
pytest tests/component/ -m "not requires_hardware" --host $IP
```

### Audio-Only Testing
```bash
pytest tests/component/audio/ tests/integration/*audio* --host $IP
```

### Display-Only Testing
```bash
pytest tests/component/display/ tests/integration/*display* --host $IP
```

### Full Test Suite
```bash
pytest tests/ --host $IP --maxfail=0 -v
```

## Expected Results by Configuration

### Minimal Hardware (Capture Only)
- Expected Pass Rate: ~85%
- Failures: Display audio, intercom, HDMI tests
- Skips: Hardware-dependent tests

### Standard Configuration (All Hardware)
- Expected Pass Rate: >95%
- Failures: Only transient/timing issues
- Skips: Optional features

### Development Environment
- Expected Pass Rate: 100%
- Failures: None (with retries)
- Skips: None

## Troubleshooting Test Failures

### Common Issues and Solutions

1. **"No HDMI sinks available"**
   - Connect at least one HDMI display
   - Verify display is powered on
   - Check HDMI cable connection

2. **"Chrome not running"**
   - Restart intercom service
   - Check Chrome installation
   - Verify USB audio connected

3. **"Timeout >30s"**
   - Network latency too high
   - System under heavy load
   - Increase test timeouts

4. **"Audio not initialized"**
   - PipeWire not running
   - WirePlumber not started
   - Check service dependencies

## Continuous Integration Considerations

For CI/CD pipelines:

1. Use dedicated test hardware
2. Ensure consistent environment
3. Mock hardware dependencies where possible
4. Separate unit/integration/system tests
5. Use test markers for selective execution

## Conclusion

The unified PipeWire architecture tests are comprehensive but require specific hardware and network configurations for complete validation. The test suite is designed to gracefully handle missing components, skipping tests that cannot run rather than failing incorrectly.