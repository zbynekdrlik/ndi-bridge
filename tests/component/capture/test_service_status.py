"""
Atomic tests for NDI capture service status.

Each test validates a single aspect of the service state.
"""

import pytest


def test_ndi_capture_service_exists(host):
    """Test that ndi-capture service unit file exists."""
    service_file = host.file("/etc/systemd/system/ndi-capture.service")
    assert service_file.exists, "ndi-capture.service unit file not found"


def test_ndi_capture_service_enabled(host):
    """Test that ndi-capture service is enabled at boot."""
    service = host.service("ndi-capture")
    assert service.is_enabled, "ndi-capture service is not enabled"


def test_ndi_capture_service_running(host):
    """Test that ndi-capture service is currently running."""
    service = host.service("ndi-capture")
    assert service.is_running, "ndi-capture service is not running"


def test_ndi_capture_process_exists(host):
    """Test that ndi-capture process is actually running."""
    result = host.run("pgrep -x ndi-capture")
    assert result.succeeded, "ndi-capture process not found"


def test_ndi_capture_binary_exists(host):
    """Test that ndi-capture binary exists and is executable."""
    binary = host.file("/opt/ndi-bridge/ndi-capture")
    assert binary.exists, "ndi-capture binary not found"
    assert binary.is_executable, "ndi-capture binary is not executable"


@pytest.mark.critical
def test_ndi_capture_service_active_state(host):
    """Test that ndi-capture service is in active (running) state."""
    result = host.run("systemctl is-active ndi-capture")
    assert result.stdout.strip() == "active", f"Service state: {result.stdout.strip()}"