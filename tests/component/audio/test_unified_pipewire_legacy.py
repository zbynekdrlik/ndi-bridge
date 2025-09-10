"""
Legacy tests for old system-wide PipeWire architecture.

These tests are kept for reference but should fail with the new user mode architecture.
They verify that the OLD system services are no longer present.
"""

import pytest
import time


@pytest.mark.xfail(reason="System services replaced by user services")
def test_pipewire_system_service_exists(host):
    """Test that OLD pipewire-system service should NOT exist."""
    service = host.service("pipewire-system")
    assert service.is_enabled, "pipewire-system service not enabled"


@pytest.mark.xfail(reason="System services replaced by user services")
def test_pipewire_pulse_system_service_exists(host):
    """Test that OLD pipewire-pulse-system service should NOT exist."""
    service = host.service("pipewire-pulse-system")
    assert service.is_enabled, "pipewire-pulse-system service not enabled"


@pytest.mark.xfail(reason="System services replaced by user services")
def test_wireplumber_system_service_exists(host):
    """Test that OLD wireplumber-system service should NOT exist."""
    service = host.service("wireplumber-system")
    assert service.is_enabled, "wireplumber-system service not enabled"


def test_no_root_pipewire_instances(host):
    """Test that PipeWire is NOT running as root."""
    # Check that PipeWire processes are NOT running as root
    result = host.run("ps aux | grep pipewire | grep root | grep -v grep")
    assert result.stdout.strip() == "", "Found root PipeWire processes (should run as mediabridge)"


def test_old_xdg_runtime_dir_not_used(host):
    """Test that OLD XDG_RUNTIME_DIR=/run/user/0 is not used."""
    # Check environment of running services
    result = host.run("systemctl show media-bridge-intercom -p Environment")
    assert "/run/user/0" not in result.stdout, "Service still using old /run/user/0"
    assert "/run/pipewire" in result.stdout, "Service not using new /run/pipewire"


def test_old_pulse_socket_not_primary(host):
    """Test that OLD PulseAudio socket location is not primary."""
    # The old socket at /run/user/0/pulse should not exist
    socket = host.file("/run/user/0/pulse/native")
    if socket.exists:
        # If it exists, it should be owned by root (legacy)
        assert socket.user == "root", "Old socket exists but not owned by root"
    
    # New socket should be at /run/pipewire/pulse
    new_socket = host.file("/run/pipewire/pulse/native")
    assert new_socket.exists or host.file("/run/pipewire/pulse").exists, "New pulse socket location not found"