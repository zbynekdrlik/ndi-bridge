# Media Bridge Testing Documentation

**SINGLE SOURCE OF TRUTH for all testing procedures and commands.**

## ⚠️ CRITICAL DEVELOPMENT RULE: TEST-FIRST REQUIREMENT

**ANY bug fix or feature implementation MUST follow this strict process:**

1. **FIRST: Write tests that FAIL and demonstrate the bug**
   - Tests must catch the actual issue (not pass with weakened assertions)
   - Tests must verify real functionality (not just check if something exists)
   - Tests must be comprehensive enough to prevent regression

2. **SECOND: Implement the fix**
   - Fix must make the tests pass without weakening them
   - Fix must not break other tests

3. **THIRD: Verify ALL tests pass (100% success required)**
   - Run complete test suite, not just the new tests
   - No skipping tests to "save time"
   - No marking tests as "known limitation" without fixing

**VIOLATIONS OF THIS RULE:**
- Writing fixes without tests first = REJECTED
- Weakening tests to make them pass = REJECTED  
- Skipping failing tests = REJECTED
- Claiming "working" with failing tests = FALSE

## Critical Rule: Always Use test-device.sh

**NEVER run pytest directly!** Always use `test-device.sh` as the entry point for all testing.

### ⚠️ CRITICAL: Test Execution Behavior

**test-device.sh RUNS ALL TESTS BY DEFAULT - IT DOES NOT STOP ON FIRST FAILURE!**

- **CONTINUES THROUGH ALL TESTS**: Even if tests fail, it continues to run the entire suite
- **NO EARLY EXIT**: There is no `--maxfail` or `-x` flag by default
- **COMPLETE RESULTS**: You will see ALL passes and failures, not just the first failure
- **AUTO-RETRY**: Failed tests are automatically retried 3 times for network issues

**IMPLICATIONS FOR DEVELOPERS:**
1. **NEVER claim "tests are working" without checking the FINAL summary**
2. **ALWAYS look for the summary line**: `X failed, Y passed, Z skipped`
3. **If you see ANY failures, the feature is NOT working**
4. **Run with --collect-only first to see how many tests SHOULD run**

The test-device.sh script:
- Handles SSH host key changes (critical for reflashed devices) 
- Sets up authentication automatically
- Runs the complete 433-test suite with proper configuration
- Provides convenient testing options

## Quick Start

### 1. Prerequisites (One-Time Setup)

```bash
# Install test dependencies
pip3 install -r tests/requirements.txt --break-system-packages

# Generate SSH key (if not already present)
ssh-keygen -t ed25519 -f ~/.ssh/ndi_test_key -N ""
```

### 2. Run All Tests (Most Common Usage)

```bash
cd /home/newlevel/devel/ndi-bridge

# Run ALL 433 tests (recommended)
./tests/test-device.sh 10.77.8.124

# Run specific test category
./tests/test-device.sh 10.77.8.124 tests/component/capture/

# Run single test file
./tests/test-device.sh 10.77.8.124 tests/component/core/test_version_info.py

# Quick SSH verification test only
./tests/test-device.sh 10.77.8.124 --collect-only
```

**IMPORTANT**: IP address is REQUIRED as first parameter. No config files or environment variables.

## Test-Device.sh Features

The enhanced test-device.sh script provides:

1. **SSH Setup**: Automatic handling of host keys and authentication
2. **All Tests**: Runs the complete 433-test suite with --maxfail=0
3. **Specific Tests**: Can run individual tests or categories
4. **Auto-Retry**: Built-in retry for network/timeout issues
5. **Color Output**: Clear success/failure indicators
6. **Fallback Auth**: Uses SSH keys first, falls back to password

## Test Architecture Overview

### Test Categories (433 total tests across 39 Python files)

```
tests/
├── component/          # Atomic tests (one test = one assertion)
│   ├── audio/         # PipeWire, ALSA, virtual devices (95 tests)
│   ├── capture/       # V4L2, NDI sender, FPS monitoring (42 tests)
│   ├── core/          # System basics, services, version (38 tests)
│   ├── display/       # DRM/KMS, HDMI, NDI receiver (28 tests)
│   ├── helpers/       # Helper scripts, menu system (67 tests)
│   ├── network/       # Networking, mDNS, time sync (31 tests)
│   └── timesync/      # PTP, NTP, time coordination (18 tests)
├── integration/       # Multi-component functional tests (89 tests)
│   ├── test_capture_to_ndi.py           # End-to-end capture
│   ├── test_display_functional.py       # Actually plays streams
│   └── test_display_pipewire_functional.py  # Audio+video together
├── system/           # Full system tests (25 tests)
│   ├── test_boot_sequence.py           # Boot process validation
│   └── test_system_resources.py        # Performance/memory
```

### Test Execution Philosophy

- **Atomic Tests**: Each test validates exactly one thing
- **Complete Coverage**: All 433 tests run by default (--maxfail=0)
- **Hardware Aware**: Tests skip gracefully if hardware missing
- **Quality Over Speed**: Thorough validation prioritized over execution time
- **Auto-Retry**: Network/timeout issues automatically retried

## Common Usage Patterns

### Development Testing
```bash
# After making changes - run all tests
./tests/test-device.sh 10.77.8.124

# Test specific component you changed
./tests/test-device.sh 10.77.8.124 tests/component/audio/

# Quick verification (critical tests only)
./tests/test-device.sh 10.77.8.124 -m critical
```

### CI/CD Testing
```bash
# Full validation for release
./tests/test-device.sh 10.77.8.124

# Component isolation
./tests/test-device.sh 10.77.8.124 tests/component/ -v

# System validation  
./tests/test-device.sh 10.77.8.124 tests/system/ tests/integration/
```

### Debugging Failed Tests
```bash
# Verbose output for debugging
./tests/test-device.sh 10.77.8.124 tests/component/audio/test_pipewire_system.py -vv

# Run single failing test
./tests/test-device.sh 10.77.8.124 tests/component/audio/test_pipewire_system.py::test_pipewire_service_running

# Run slow functional tests (most important tests)
./tests/test-device.sh 10.77.8.124 -m slow
```

## Understanding Test Results

### Expected Results on Healthy Media Bridge Device:
- **~400+ tests passed** (exact number depends on hardware configuration)
- **Some skipped tests** (normal for missing optional hardware)
- **Zero failed tests** (on properly configured device)
- **Total runtime**: 5-10 minutes for complete suite

### Common Result Patterns:
```bash
========================== 410 passed, 23 skipped in 8m 32s ==========================
```

- **PASSED**: Test succeeded - feature working correctly
- **FAILED**: Test failed - indicates problem requiring investigation  
- **SKIPPED**: Optional feature not present - normal and expected
- **ERROR**: Test couldn't run - usually connectivity/setup issue

### Hardware-Dependent Tests:

1. **HDMI/Display Tests** - Skip if no monitors connected
2. **USB Audio Tests** - Skip if no USB audio device  
3. **Intercom Tests** - Skip if Chrome/USB audio not available
4. **Performance Tests** - May timeout on slow systems

## Test Markers for Selective Execution

Tests are tagged with markers for selective execution:

- `critical` - Must pass for basic functionality
- `slow` - Takes >5 seconds to complete
- `requires_hardware` - Needs specific hardware connected
- `destructive` - Modifies system state
- `network` - Requires network connectivity
- `audio` - Audio-related functionality
- `display` - Display/video functionality

### Examples:
```bash
# Run only critical tests (fastest validation)
./tests/test-device.sh 10.77.8.124 -m critical

# Run slow functional tests (thorough validation)  
./tests/test-device.sh 10.77.8.124 -m slow

# Run only audio tests
./tests/test-device.sh 10.77.8.124 -m audio

# Run hardware tests only
./tests/test-device.sh 10.77.8.124 -m requires_hardware
```

## Hardware Requirements for Full Testing

### Minimum Configuration (Basic Testing):
- Media Bridge device with network connection
- SSH access configured
- No additional hardware required
- **Expected**: ~350 tests pass, ~80 skip

### Standard Configuration (Complete Testing):  
- USB 3.0 capture device connected
- USB audio device (CSCTek or compatible) 
- At least 1 HDMI display connected with audio
- Network with NDI streams available
- **Expected**: ~410+ tests pass, ~20 skip

### Development Configuration (Zero Skips):
- Multiple USB devices connected
- Multiple HDMI displays connected
- Access to live NDI streams
- Chrome browser configured
- **Expected**: 433 tests pass, 0 skip

## Troubleshooting

### Common Issues and Solutions:

1. **"Connection timeout" / "Connection refused"**
   ```bash
   # Check device is accessible
   ping 10.77.8.124
   
   # Try SSH manually
   ssh root@10.77.8.124
   ```

2. **"SSH host key verification failed"**
   ```bash
   # test-device.sh handles this automatically
   # If still issues, manually clear:
   ssh-keygen -f ~/.ssh/known_hosts -R 10.77.8.124
   ```

3. **"No such file or directory: test-device.sh"**
   ```bash
   # Must run from repository root
   cd /home/newlevel/devel/ndi-bridge
   ./tests/test-device.sh 10.77.8.124
   ```

4. **Tests failing unexpectedly**
   ```bash
   # Run with verbose output
   ./tests/test-device.sh 10.77.8.124 -v
   
   # Check device status
   ssh root@10.77.8.124 "systemctl status"
   ```

5. **"Permission denied" errors**
   ```bash
   # Ensure SSH key setup
   ls -la ~/.ssh/ndi_test_key*
   
   # test-device.sh creates keys automatically if missing
   ```

### Test Infrastructure Issues:

If tests are failing due to infrastructure problems:
- See [PIPEWIRE.md](PIPEWIRE.md) - Audio system architecture  
- Check device logs: `ssh root@DEVICE_IP "journalctl -f"`
- Verify hardware requirements (USB devices, HDMI displays, network)

## Advanced Usage

### Custom pytest Options:
```bash
# Any additional pytest flags pass through
./tests/test-device.sh 10.77.8.124 --tb=short --durations=10
```

## Integration with Development Workflow

### Before Committing Code:
```bash
# Always run tests before committing
./tests/test-device.sh 10.77.8.124

# For urgent fixes, at minimum run critical tests
./tests/test-device.sh 10.77.8.124 -m critical
```

### After Flashing New Image:
```bash
# Full validation of new build
./tests/test-device.sh 10.77.8.124
```

### Debugging New Features:
```bash
# Test specific component you're working on
./tests/test-device.sh 10.77.8.124 tests/component/your-feature/ -vv
```

## Legacy Test Scripts (Deprecated)

The following approaches are **DEPRECATED** - use test-device.sh instead:

- Any direct pytest commands - Use `./tests/test-device.sh` instead
- Custom test scripts - Use `./tests/test-device.sh` instead

## Writing New Tests

When adding new tests, follow these guidelines:

### 1. Atomic Test Principle
Each test function validates exactly one behavior:

```python
def test_capture_device_exists(host):
    """Test that video capture device exists."""
    assert host.file("/dev/video0").exists

def test_capture_service_running(host):
    """Test that capture service is active.""" 
    assert host.service("ndi-capture").is_running
```

### 2. Place in Correct Category
- `component/` - Single component, atomic tests
- `integration/` - Multi-component, functional tests  
- `system/` - Full end-to-end system tests

### 3. Use Appropriate Markers
```python
@pytest.mark.slow
@pytest.mark.requires_hardware
def test_actual_video_capture(host):
    """Test that video capture produces frames."""
    # Test implementation
```

### 4. Handle Missing Hardware Gracefully
```python
def test_usb_audio_device(host):
    """Test USB audio device is present."""
    audio_devices = host.run("lsusb | grep -i audio")
    if not audio_devices.succeeded:
        pytest.skip("No USB audio device connected")
    
    assert "CSCTek" in audio_devices.stdout
```

## Summary

- **ALWAYS use test-device.sh** - never run pytest directly
- **IP address required** as first parameter  
- **433 tests total** across comprehensive test suite
- **~400 should pass** on healthy device
- **Hardware dependencies** cause expected skips
- **Complete validation** takes 5-10 minutes
- **Single source of truth** for all testing procedures

For questions or issues with testing, refer to this document first. All test procedures and commands should be documented here.