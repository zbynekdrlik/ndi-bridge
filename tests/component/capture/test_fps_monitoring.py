"""
Atomic tests for capture FPS monitoring and stability.

Tests frame rate monitoring and performance metrics.
"""

import pytest
import time


def test_fps_file_exists(host):
    """Test that FPS metrics file exists."""
    fps_file = host.file("/var/run/ndi-bridge/fps")
    assert fps_file.exists, "FPS metrics file not found"


def test_fps_value_is_numeric(host):
    """Test that FPS value is a valid number."""
    fps_content = host.file("/var/run/ndi-bridge/fps").content_string.strip()
    try:
        fps = float(fps_content)
        assert True
    except ValueError:
        pytest.fail(f"FPS value is not numeric: {fps_content}")


@pytest.mark.critical
def test_fps_within_acceptable_range(host):
    """Test that FPS is within acceptable range (29-31 fps for 30fps target)."""
    fps = float(host.file("/var/run/ndi-bridge/fps").content_string.strip())
    assert 29.0 <= fps <= 31.0, f"FPS {fps} outside acceptable range"


def test_frames_captured_increasing(host):
    """Test that frame counter is increasing over time."""
    # First reading
    frames1 = int(host.file("/var/run/ndi-bridge/frames_captured").content_string.strip())
    
    # Wait and read again
    time.sleep(2)
    frames2 = int(host.file("/var/run/ndi-bridge/frames_captured").content_string.strip())
    
    assert frames2 > frames1, f"Frames not increasing: {frames1} -> {frames2}"


def test_dropped_frames_file_exists(host):
    """Test that dropped frames counter file exists."""
    dropped_file = host.file("/var/run/ndi-bridge/frames_dropped")
    assert dropped_file.exists, "Dropped frames counter not found"


@pytest.mark.performance
def test_dropped_frames_percentage_low(host):
    """Test that dropped frame percentage is below 1%."""
    captured = int(host.file("/var/run/ndi-bridge/frames_captured").content_string.strip())
    dropped = int(host.file("/var/run/ndi-bridge/frames_dropped").content_string.strip())
    
    if captured > 0:
        drop_rate = (dropped / captured) * 100
        assert drop_rate < 1.0, f"High drop rate: {drop_rate:.2f}%"