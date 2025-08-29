# NDI Bridge Automated Testing Framework

## Overview
Comprehensive automated testing suite for NDI Bridge USB appliance. Tests deployment, capture, display, and audio functionality without requiring physical USB handling.

## Quick Start

```bash
# Run all standard tests on box at 10.77.9.143
./run_tests.sh -i 10.77.9.143

# Quick capture-only test
./run_tests.sh -i 10.77.9.143 --quick

# Full deployment test (requires ndi-bridge.img)
./run_tests.sh -i 10.77.9.143 --all

# Run with long-duration stability tests
./run_tests.sh -i 10.77.9.143 --long
```

## Test Suites

### 1. Deployment Test (`test_full_deployment.sh`)
- Deploys image to box without USB
- Verifies services start correctly
- Tests reboot persistence
- Validates network and web interface

### 2. Capture Test (`test_capture.sh`)
- V4L2 device detection
- NDI stream broadcasting
- FPS stability monitoring
- Service restart recovery

### 3. Display Test (`test_display.sh`)
- NDI stream discovery
- Stream assignment/removal
- Multiple display support
- Stream switching

### 4. Audio Test (`test_audio.sh`)
- ALSA device detection
- Audio output to HDMI
- Streams with/without audio
- Audio format verification

## Configuration

Edit `fixtures/test_config.env`:
```bash
TEST_BOX_IP="10.77.9.143"
TEST_NDI_STREAM="RESOLUME-SNV (cg-obs)"
TEST_NDI_STREAM_NO_AUDIO="RESOLUME-SNV (Arena - VJ)"
```

## Requirements

- SSH access to test box (root/newlevel)
- `sshpass` installed on test machine
- NDI streams available on network
- Built image file for deployment tests

## Test Development

### Adding New Tests

1. Create test in `integration/` directory
2. Source required libraries:
```bash
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"
```

3. Use assertion functions:
```bash
assert_service_active "ndi-capture"
assert_display_has_audio "1"
assert_fps_in_range "30"
```

4. Record results:
```bash
record_test "Test Name" "PASS"
record_test "Test Name" "FAIL" "Error message"
```

### Library Functions

**common.sh**
- `box_ssh` - Execute commands on box
- `box_ping` - Check connectivity
- `box_service_status` - Get service status
- `parse_status_value` - Parse status files

**assertions.sh**
- `assert_equals` - Compare values
- `assert_service_active` - Check service
- `assert_display_has_video` - Verify video
- `assert_display_has_audio` - Verify audio

**box_control.sh**
- `box_reboot` - Reboot box
- `box_deploy_image` - Fast deployment
- `box_assign_display` - Assign NDI stream
- `box_monitor_capture` - Monitor FPS

## Output

- **Console**: Real-time test progress
- **Logs**: `tests/logs/test_*.log`
- **Reports**: `tests/logs/test_report_*.txt`

## CI/CD Integration

```bash
# In CI pipeline
if ./tests/run_tests.sh -i $TEST_BOX_IP --all; then
    echo "Tests passed, ready to merge"
else
    echo "Tests failed, check logs"
    exit 1
fi
```

## Troubleshooting

- **Connection failed**: Check box IP and network
- **Service not active**: Check build and deployment
- **No NDI streams**: Verify NDI sources on network
- **Audio tests fail**: Check HDMI connections