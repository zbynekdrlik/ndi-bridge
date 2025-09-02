# NDI Bridge Test Suite

## Overview
Modern pytest-based testing framework for NDI Bridge USB appliance using testinfra for agentless infrastructure testing.

## Quick Start

```bash
# Install test dependencies
pip3 install -r requirements.txt

# Configure test target
cp test_config.yaml.example test_config.yaml
nano test_config.yaml  # Update with your device IP

# Run tests
pytest tests/ -v                           # All tests with verbose output
pytest tests/component/core/ -q            # Core tests, quiet mode
pytest tests/ -m critical                  # Only critical tests
pytest tests/ --tb=no --co                # List all tests without running
```

## Test Organization

```
tests/
├── component/          # Unit tests for individual components
│   ├── audio/         # Audio system and intercom tests
│   ├── capture/       # Video capture and monitoring tests
│   ├── core/          # Core system services tests
│   ├── display/       # Display output tests
│   ├── network/       # Network configuration tests
│   ├── helpers/       # Helper script tests
│   ├── timesync/      # Time synchronization tests
│   └── web/           # Web interface tests
├── integration/       # End-to-end integration tests
├── performance/       # Performance and stress tests
├── system/           # System-level tests
├── unit/             # Unit tests for configuration
└── fixtures/         # Test fixtures and utilities
```

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