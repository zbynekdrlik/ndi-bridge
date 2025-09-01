"""
Atomic tests for helper scripts functionality.

Tests the NDI Bridge helper scripts and utilities.
"""

import pytest


def test_ndi_bridge_info_script_exists(host):
    """Test that ndi-bridge-info script exists."""
    script = host.file("/usr/local/bin/ndi-bridge-info")
    assert script.exists, "ndi-bridge-info script not found"


def test_ndi_bridge_info_script_executable(host):
    """Test that ndi-bridge-info script is executable."""
    script = host.file("/usr/local/bin/ndi-bridge-info")
    if script.exists:
        assert script.mode & 0o111, "ndi-bridge-info is not executable"


def test_ndi_bridge_info_runs_successfully(host):
    """Test that ndi-bridge-info runs without error."""
    result = host.run("ndi-bridge-info")
    assert result.rc == 0, f"ndi-bridge-info failed: {result.stderr}"


def test_ndi_bridge_logs_script_exists(host):
    """Test that ndi-bridge-logs script exists."""
    script = host.file("/usr/local/bin/ndi-bridge-logs")
    assert script.exists, "ndi-bridge-logs script not found"


def test_ndi_bridge_logs_script_executable(host):
    """Test that ndi-bridge-logs script is executable."""
    script = host.file("/usr/local/bin/ndi-bridge-logs")
    if script.exists:
        assert script.mode & 0o111, "ndi-bridge-logs is not executable"


def test_ndi_bridge_set_name_script_exists(host):
    """Test that ndi-bridge-set-name script exists."""
    script = host.file("/usr/local/bin/ndi-bridge-set-name")
    assert script.exists, "ndi-bridge-set-name script not found"


def test_ndi_bridge_restart_script_exists(host):
    """Test that ndi-bridge-restart script exists."""
    script = host.file("/usr/local/bin/ndi-bridge-restart")
    if not script.exists:
        # Script might not exist, skip test
        pytest.skip("ndi-bridge-restart script not found - optional feature")


def test_ndi_bridge_welcome_script_exists(host):
    """Test that ndi-bridge-welcome script exists."""
    script = host.file("/usr/local/bin/ndi-bridge-welcome")
    assert script.exists, "ndi-bridge-welcome script not found"


def test_ndi_bridge_welcome_service_enabled(host):
    """Test that ndi-bridge-welcome service is enabled."""
    service = host.service("ndi-bridge-welcome")
    assert service.is_enabled, "ndi-bridge-welcome service not enabled"


def test_ndi_bridge_collector_script_exists(host):
    """Test that ndi-bridge-collector script exists."""
    script = host.file("/usr/local/bin/ndi-bridge-collector")
    assert script.exists, "ndi-bridge-collector script not found"


def test_ndi_bridge_collector_service_enabled(host):
    """Test that ndi-bridge-collector service is enabled."""
    service = host.service("ndi-bridge-collector")
    assert service.is_enabled, "ndi-bridge-collector service not enabled"


def test_ndi_bridge_collector_service_running(host):
    """Test that ndi-bridge-collector service is running."""
    service = host.service("ndi-bridge-collector")
    assert service.is_running, "ndi-bridge-collector service not running"


@pytest.mark.helpers
def test_helper_scripts_in_path(host):
    """Test that helper scripts are in system PATH."""
    result = host.run("which ndi-bridge-info")
    assert result.rc == 0, "ndi-bridge-info not in PATH"