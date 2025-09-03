# NDI Bridge Testing Architecture

## Overview

The NDI Bridge project uses pytest with testinfra for comprehensive hardware testing via SSH. All tests follow atomic testing principles (one test = one assertion) and are designed to run on actual hardware devices.

**Test Framework**: pytest + testinfra  
**Remote Execution**: SSH-based testing on real hardware  
**Test Philosophy**: Atomic tests with single assertions  
**Success Criteria**: 100% pass rate required (no partial success)

## Test Categories

### 1. Component Tests (`component/`)
Atomic tests that verify individual components exist and are configured correctly.

- **audio/**: Audio subsystem tests (ALSA, PipeWire, HDMI audio)
- **display/**: Display capability tests (DRM/KMS, HDMI ports, PipeWire audio)
- **capture/**: Video capture tests (V4L2, USB devices)
- **network/**: Network configuration tests
- **core/**: Core system tests
- **intercom/**: VDO.Ninja intercom tests

### 2. Integration Tests (`integration/`)
Functional tests that exercise real system behavior with multiple components.

- **test_display_functional.py**: Actually plays NDI streams with video/audio
- **test_display_pipewire_functional.py**: Tests PipeWire audio with different HDMI ports
- **test_capture_to_ndi.py**: Tests capture to NDI streaming pipeline

### 3. System Tests (`system/`)
End-to-end tests of complete workflows.

### 4. Performance Tests (`performance/`)
Benchmarks and metrics validation.

## PipeWire Audio Implementation (2025)

The ndi-display component now uses PipeWire instead of ALSA for unified audio management:

### System Architecture
- **System-wide PipeWire**: Runs as root with pipewire-system service
- **PulseAudio Compatibility**: pipewire-pulse-system provides PA API
- **Session Manager**: wireplumber-system manages audio routing
- **HDMI Audio Routing**: Direct routing to monitor speakers via HDMI

### Key Features Tested
1. **Multiple HDMI Ports**: Intel N100 supports 3 HDMI outputs (HDMI-A-1, HDMI-A-2, HDMI-A-3)
2. **Dynamic Port Selection**: Audio follows display ID (0, 1, or 2)
3. **Low Latency**: 256 sample buffer @ 48kHz = ~5.3ms latency
4. **Hardware Acceleration**: Uses Intel GPU for video scaling
5. **Volume Management**: HDMI volume automatically set to 100% on display start

### Test Files Created for PipeWire

#### Component Tests
- `test_ndi_display_pipewire.py`: 28 atomic tests for PipeWire services and configuration
- `test_hdmi_audio_routing.py`: 20 tests for HDMI audio routing and port detection
- `test_hdmi_volume_100_percent.py`: 13 tests for HDMI volume verification (ensures 100% volume)

#### Integration Tests
- `test_display_pipewire_functional.py`: 8 functional tests including:
  - Audio initialization on each display ID
  - PipeWire client registration
  - Audio continuity during playback
  - HDMI port switching
  - Latency verification

## Running Tests

### Configuration
Tests use `test_config.yaml` for persistent device configuration:

```yaml
host: 10.77.8.110
ssh_user: root
ssh_pass: newlevel
ssh_key: ~/.ssh/ndi_test_key
```

### Basic Commands

```bash
# Run all tests
pytest tests/ --host 10.77.8.110 --ssh-key ~/.ssh/ndi_test_key -v

# Run specific category
pytest tests/component/display/ --host 10.77.8.110 --ssh-key ~/.ssh/ndi_test_key

# Run with markers
pytest tests/ -m "audio and display" --host 10.77.8.110 --ssh-key ~/.ssh/ndi_test_key

# Quick summary
pytest tests/ --host 10.77.8.110 --ssh-key ~/.ssh/ndi_test_key -q --tb=no
```

## HDMI Volume Management

The NDI display system automatically sets HDMI audio volume to 100% to ensure consistent audio output. This is critical for reliable audio playback across different displays and monitors.

### Implementation Details
- **ndi-display-launcher**: Calls audio setup script after starting display
- **ndi-display-audio-setup**: Sets HDMI sink volume to 100% using `pactl set-sink-volume`
- **Timing**: Volume set after PipeWire initialization and HDMI sink detection

### Tests for Volume Verification
The `test_hdmi_volume_100_percent.py` file contains 13 atomic tests:
1. Script existence and permissions
2. Volume command presence in scripts
3. PipeWire volume control functionality
4. Volume persistence after display start
5. Functional test with actual NDI stream

## Test Results Summary

### Current Status (2025-09-03)
- **Total Tests**: 129 audio/display tests (updated with volume tests)
- **Component Tests**: 104 tests (audio: 35, display: 69 including 13 volume tests)
- **Integration Tests**: 8 PipeWire functional tests
- **Pass Rate**: ~99% (1 test needs environment-specific fix)

### PipeWire Audio Test Coverage

#### ✅ Verified Working
- PipeWire system services running
- HDMI audio sink detection
- Multiple HDMI port support
- Audio initialization for all display IDs
- Low latency configuration (256 samples)
- PipeWire client registration
- Audio continuity during playback

#### ⚠️ Environment-Specific
- HDMI mixer controls (depends on specific hardware)
- Display 0 console binding (requires console unbinding)

## Common Test Patterns

### Atomic Test Example
```python
def test_pipewire_system_service_running(host):
    """Test that pipewire-system service is running."""
    service = host.service("pipewire-system")
    assert service.is_running, "pipewire-system service not running"
```

### Functional Test Example
```python
def test_display_pipewire_audio_display_2(host):
    """Test PipeWire audio output with display ID 2."""
    # Unbind console
    host.run("echo 0 > /sys/class/vtconsole/vtcon1/bind")
    
    # Start display with audio
    cmd = "timeout 10 /opt/media-bridge/ndi-display 'STREAM' 2 2>&1"
    result = host.run(cmd)
    
    # Verify audio initialized
    assert 'Audio output initialized' in result.stdout
```

## Troubleshooting

### PipeWire Audio Issues

1. **Services Not Running**
   ```bash
   systemctl start pipewire-system pipewire-pulse-system wireplumber-system
   ```

2. **No HDMI Audio Sinks**
   - Check monitor is connected and powered on
   - Verify HDMI cable supports audio
   - Check `pactl list sinks short | grep hdmi`

3. **Console Blocking Display**
   - Unbind console: `echo 0 > /sys/class/vtconsole/vtcon1/bind`
   - Or configure display: `ndi-display-config 0`

### Test Failures

1. **SSH Connection Issues**
   - Verify device IP is correct
   - Check SSH key is installed: `ssh-copy-id -i ~/.ssh/ndi_test_key root@IP`

2. **Timeout Errors**
   - Increase timeout: `pytest --timeout=60`
   - Check device is not under heavy load

## Future Improvements

1. **Automated Performance Testing**
   - Add audio latency measurements
   - Monitor CPU usage during playback
   - Test with 4K streams

2. **Edge Case Testing**
   - Hot-plug HDMI monitor switching
   - Audio recovery after PipeWire restart
   - Multiple simultaneous displays

3. **CI/CD Integration**
   - GitHub Actions workflow for automated testing
   - Test result badges in README
   - Automatic regression detection

## Contributing

When adding new tests:
1. Follow atomic testing principle (one assertion per test)
2. Place tests in appropriate category directory
3. Use descriptive test names: `test_<component>_<behavior>_<expected>`
4. Add appropriate markers (@pytest.mark.audio, @pytest.mark.display)
5. Update this documentation with new test coverage

## References

- [pytest Documentation](https://docs.pytest.org/)
- [testinfra Documentation](https://testinfra.readthedocs.io/)
- [PipeWire Wiki](https://gitlab.freedesktop.org/pipewire/pipewire/-/wikis/home)
- [NDI SDK Documentation](https://www.ndi.tv/sdk/)