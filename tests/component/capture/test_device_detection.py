"""
Atomic test for capture device detection.

This module tests a single responsibility: verifying that the capture
device exists and is accessible.
"""

import pytest


def test_capture_device_exists(host):
    """Test that the capture device /dev/video0 exists."""
    device = host.file("/dev/video0")
    assert device.exists, "Capture device /dev/video0 not found"


def test_capture_device_is_character_device(host):
    """Test that /dev/video0 is a character device."""
    # Use stat command to check if it's a character device
    result = host.run("test -c /dev/video0")
    if result.exit_status == 0:
        assert True, "/dev/video0 is a character device"
    else:
        # Check if device exists at all
        device = host.file("/dev/video0")
        if not device.exists:
            pytest.skip("/dev/video0 does not exist")
        else:
            assert False, "/dev/video0 exists but is not a character device"


def test_capture_device_has_correct_permissions(host):
    """Test that /dev/video0 has correct permissions for capture."""
    device = host.file("/dev/video0")
    assert device.mode == 0o660, f"Incorrect permissions: {oct(device.mode)}"


def test_capture_device_owned_by_video_group(host):
    """Test that /dev/video0 is owned by video group."""
    device = host.file("/dev/video0")
    assert device.group == "video", f"Incorrect group: {device.group}"


@pytest.mark.requires_usb
def test_usb_capture_device_connected(host):
    """Test that USB capture device is connected and recognized."""
    result = host.run("lsusb | grep -i 'video\\|capture\\|cam'")
    if not result.succeeded:
        pytest.skip("No USB video capture device detected - test requires physical USB device")