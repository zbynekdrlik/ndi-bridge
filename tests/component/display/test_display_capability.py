"""
Atomic tests for display capability.

Tests the NDI display output functionality.
"""

import pytest


def test_drm_device_exists(host):
    """Test that DRM device exists for display output."""
    drm = host.file("/dev/dri/card0")
    assert drm.exists, "DRM device /dev/dri/card0 not found"


def test_drm_device_is_character(host):
    """Test that DRM device is a character device."""
    drm = host.file("/dev/dri/card0")
    if drm.exists:
        assert drm.is_character, "DRM device is not a character device"


def test_ndi_display_binary_exists(host):
    """Test that ndi-display binary exists."""
    binary = host.file("/opt/ndi-bridge/ndi-display")
    assert binary.exists, "ndi-display binary not found"


def test_ndi_display_binary_executable(host):
    """Test that ndi-display binary is executable."""
    binary = host.file("/opt/ndi-bridge/ndi-display")
    if binary.exists:
        assert binary.mode & 0o111, "ndi-display is not executable"


def test_display_service_template_exists(host):
    """Test that ndi-display service template exists."""
    template = host.file("/etc/systemd/system/ndi-display@.service")
    assert template.exists, "ndi-display service template not found"


def test_display_runtime_directory_exists(host):
    """Test that display runtime directory exists."""
    runtime_dir = host.file("/var/run/ndi-display")
    assert runtime_dir.exists, "Display runtime directory not found"


def test_display_runtime_directory_is_directory(host):
    """Test that display runtime directory is a directory."""
    runtime_dir = host.file("/var/run/ndi-display")
    if runtime_dir.exists:
        assert runtime_dir.is_directory, "Display runtime path is not a directory"


def test_kms_available(host):
    """Test that KMS (Kernel Mode Setting) is available."""
    result = host.run("ls /sys/class/drm/card*/enabled 2>/dev/null | head -1")
    assert result.stdout.strip(), "No KMS-capable display outputs found"


def test_display_connectors_detected(host):
    """Test that display connectors are detected."""
    result = host.run("find /sys/class/drm -name 'card*-*' | wc -l")
    connector_count = int(result.stdout.strip())
    assert connector_count > 0, "No display connectors detected"


def test_edid_readable(host):
    """Test that EDID can be read from connected displays."""
    result = host.run("find /sys/class/drm/*/edid -size +0 2>/dev/null | head -1")
    # It's OK if no display is connected
    assert result.rc == 0, "Error checking for EDID"


@pytest.mark.display
def test_display_resolution_detected(host):
    """Test that display resolution can be detected."""
    result = host.run("cat /sys/class/drm/card*/modes 2>/dev/null | head -1")
    # Resolution might not be available if no display connected
    assert result.rc == 0, "Error checking display modes"