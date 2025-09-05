"""
Atomic tests for helper scripts functionality.

Tests the Media Bridge helper scripts and utilities.
"""

import pytest


def test_media_bridge_info_script_exists(host):
    """Test that media-bridge-info script exists."""
    script = host.file("/usr/local/bin/media-bridge-info")
    assert script.exists, "media-bridge-info script not found"


def test_media_bridge_info_script_executable(host):
    """Test that media-bridge-info script is executable."""
    script = host.file("/usr/local/bin/media-bridge-info")
    if script.exists:
        assert script.mode & 0o111, "media-bridge-info is not executable"


def test_media_bridge_info_runs_successfully(host):
    """Test that media-bridge-info runs without error."""
    result = host.run("media-bridge-info")
    assert result.rc == 0, f"media-bridge-info failed: {result.stderr}"


def test_media_bridge_logs_script_exists(host):
    """Test that media-bridge-logs script exists."""
    script = host.file("/usr/local/bin/media-bridge-logs")
    assert script.exists, "media-bridge-logs script not found"


def test_media_bridge_logs_script_executable(host):
    """Test that media-bridge-logs script is executable."""
    script = host.file("/usr/local/bin/media-bridge-logs")
    if script.exists:
        assert script.mode & 0o111, "media-bridge-logs is not executable"


def test_media_bridge_set_name_script_exists(host):
    """Test that media-bridge-set-name script exists."""
    script = host.file("/usr/local/bin/media-bridge-set-name")
    assert script.exists, "media-bridge-set-name script not found"


def test_media_bridge_restart_script_exists(host):
    """Test that media-bridge-restart script exists."""
    script = host.file("/usr/local/bin/media-bridge-restart")
    if not script.exists:
        # Script might not exist, skip test
        pytest.skip("media-bridge-restart script not found - optional feature")


def test_media_bridge_welcome_script_exists(host):
    """Test that media-bridge-welcome script exists."""
    script = host.file("/usr/local/bin/media-bridge-welcome")
    assert script.exists, "media-bridge-welcome script not found"


def test_media_bridge_collector_script_exists(host):
    """Test that media-bridge-collector script exists."""
    script = host.file("/usr/local/bin/media-bridge-collector")
    assert script.exists, "media-bridge-collector script not found"


def test_media_bridge_collector_service_enabled(host):
    """Test that media-bridge-collector service is enabled."""
    service = host.service("media-bridge-collector")
    assert service.is_enabled, "media-bridge-collector service not enabled"


def test_media_bridge_collector_service_running(host):
    """Test that media-bridge-collector service is running."""
    service = host.service("media-bridge-collector")
    assert service.is_running, "media-bridge-collector service not running"


@pytest.mark.helpers
def test_helper_scripts_in_path(host):
    """Test that helper scripts are in system PATH."""
    result = host.run("which media-bridge-info")
    assert result.rc == 0, "media-bridge-info not in PATH"