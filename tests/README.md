# Media Bridge Test Suite

## Overview
Modern pytest-based testing framework for Media Bridge USB appliance using testinfra for agentless infrastructure testing.

## Quick Start

### CRITICAL: ALWAYS run test-device.sh FIRST!

```bash
# STEP 1: MANDATORY - Setup SSH and handle key issues
cd /home/newlevel/devel/ndi-bridge
./tests/test-device.sh <DEVICE_IP>  # e.g., ./tests/test-device.sh 10.77.8.124

# STEP 2: Run the test suite (AFTER test-device.sh succeeds)
pytest tests/ --host <DEVICE_IP> --ssh-key ~/.ssh/ndi_test_key -v

# Complete example:
./tests/test-device.sh 10.77.8.124
pytest tests/ --host 10.77.8.124 --ssh-key ~/.ssh/ndi_test_key -v
```

### Why test-device.sh is REQUIRED:
- Removes old SSH host keys (critical for reflashed devices)
- Sets up proper authentication (SSH key or password)
- Tests will timeout or hang without this step
- This is MANDATORY, not optional

### Additional Test Commands (AFTER running test-device.sh):
```bash
# Install test dependencies (one-time setup)
pip3 install -r requirements.txt

# Run specific test categories
pytest tests/component/core/ --host <DEVICE_IP> --ssh-key ~/.ssh/ndi_test_key -q
pytest tests/ -m critical --host <DEVICE_IP> --ssh-key ~/.ssh/ndi_test_key
pytest tests/ --host <DEVICE_IP> --ssh-key ~/.ssh/ndi_test_key --tb=no --co  # List tests
```

## Test Organization

```
tests/
├── component/          # ATOMIC tests - check ONE thing (exists/enabled/running)
│   ├── audio/         # Audio device exists, ALSA configured
│   ├── capture/       # Device exists, service running, metrics files
│   ├── core/          # Core services enabled/running
│   ├── display/       # DRM devices exist, service templates valid
│   ├── network/       # Network interfaces, DHCP status
│   ├── helpers/       # Helper scripts exist and executable
│   ├── timesync/      # PTP/NTP services configured
│   └── web/           # Web server running, endpoints respond
├── integration/       # FUNCTIONAL tests - actually USE the system
│   ├── test_capture_to_ndi.py     # Multi-component interaction
│   └── test_display_functional.py  # Actually plays streams for 30s
├── performance/       # Performance benchmarks and stress tests
├── system/           # Full end-to-end system workflows
├── unit/             # Pure logic tests (no device needed)
└── fixtures/         # Shared test utilities and helpers
```

### Important: Test Placement Rules

**Component Tests (Atomic)**
- Check that something EXISTS (file, device, service)
- Check that something is CONFIGURED (enabled, has permissions)
- Check that something is RUNNING (service active, process exists)
- DO NOT actually use the feature (no streaming, no audio playback)

**Integration Tests (Functional)**
- Actually USE the system as a user would
- Play NDI streams to HDMI output
- Capture video and verify NDI transmission
- Record/play audio through devices
- Test multi-component interactions

**Example:**
- `component/display/` - Check DRM device exists, service is valid
- `integration/test_display_functional.py` - Actually play CG stream for 30 seconds with audio

## Configuration

### test_config.yaml
Primary configuration method - persists across sessions:
```yaml
host: 10.77.9.188
ssh_user: root
ssh_pass: newlevel
ssh_key: ~/.ssh/ndi_test_key  # Optional, recommended
```

### Configuration Priority
1. Command line arguments (highest)
2. test_config.yaml file
3. Environment variables
4. Default values (lowest)

## Test Categories

Tests are marked with pytest markers for selective execution:

- `@pytest.mark.critical` - Essential functionality
- `@pytest.mark.slow` - Long-running tests (>10s)
- `@pytest.mark.performance` - Performance benchmarks
- `@pytest.mark.requires_usb` - Needs USB device connected
- `@pytest.mark.destructive` - Modifies system state

Run specific categories:
```bash
pytest -m critical              # Only critical tests
pytest -m "not slow"           # Skip slow tests
pytest -m "critical and not requires_usb"  # Critical tests without USB
```

## Parallel Execution

```bash
pytest -n auto                  # Auto-detect CPU cores
pytest -n 4                     # Use 4 parallel workers
```

## Output Formats

```bash
pytest --tb=short               # Short traceback
pytest --tb=no                  # No traceback
pytest --tb=line               # One line per failure
pytest -v                       # Verbose output
pytest -q                       # Quiet mode
pytest --html=report.html       # HTML report
pytest --junit-xml=results.xml # JUnit XML for CI/CD
```

## SSH Key Setup

For passwordless testing (recommended for CI/CD):
```bash
ssh-keygen -t rsa -b 2048 -f ~/.ssh/ndi_test_key -N ""
./test-device.sh 10.77.9.188   # Handles key setup automatically
```

## Writing Tests

### Atomic Test Pattern
One test = one assertion for clear failure identification:

```python
def test_ssh_service_enabled(host):
    """Test that SSH service is enabled."""
    service = host.service("ssh")
    assert service.is_enabled

def test_ssh_service_running(host):
    """Test that SSH service is running."""
    service = host.service("ssh")
    assert service.is_running
```

### Using Fixtures
```python
def test_with_capture_service(host, capture_service):
    """Test using capture service fixture."""
    assert capture_service.is_running
    assert capture_service.is_enabled
```

## CI/CD Integration

```yaml
# Example GitHub Actions
- name: Run Tests
  run: |
    pip3 install -r tests/requirements.txt
    pytest tests/ --tb=no --junit-xml=results.xml
    
- name: Upload Results
  uses: actions/upload-artifact@v2
  with:
    name: test-results
    path: results.xml
```

## Troubleshooting

### Common Issues
- **SSH timeout**: Check device IP and network connectivity
- **Permission denied**: Verify SSH credentials in test_config.yaml
- **Import errors**: Install dependencies with `pip3 install -r requirements.txt`
- **Tests skipped**: Check markers and device requirements

### Debug Mode
```bash
pytest -vv --tb=long            # Maximum verbosity
pytest --pdb                    # Drop to debugger on failure
pytest --lf                     # Run last failed tests only
pytest --ff                     # Run failed tests first
```

## Test Development

### Adding New Tests
1. Create test file following naming convention: `test_*.py`
2. Import required fixtures from conftest.py
3. Write atomic tests with descriptive names
4. Add appropriate markers for categorization

### Running Specific Tests
```bash
pytest tests/component/core/test_core_services.py::test_ssh_service_running
pytest -k "ssh"                 # Run tests matching "ssh"
pytest --co -q                  # List all tests
```

## Performance Monitoring

```bash
pytest --durations=10           # Show 10 slowest tests
pytest --benchmark-only         # Run only benchmark tests
```