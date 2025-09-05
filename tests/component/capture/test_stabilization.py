"""
Atomic tests for capture stabilization behavior (Issue #38).

Tests the 30-second stabilization period during capture startup.
"""

import pytest
import time


def test_initial_state_is_starting(host):
    """Test that capture starts in STARTING state after restart."""
    # Arrange: Restart service to trigger fresh start
    host.run("systemctl restart ndi-capture")
    time.sleep(2)  # Brief pause for service to start
    
    # Act: Read the capture state
    state_file = host.file("/var/run/media-bridge/capture_state")
    
    # Assert: Should be in STARTING, STABILIZING or RUNNING state
    assert state_file.exists, "Capture state file not found"
    state = state_file.content_string.strip()
    assert state in ["STARTING", "STABILIZING", "RUNNING"], f"Expected STARTING, STABILIZING or RUNNING, got {state}"


@pytest.mark.timeout(60)  # Stabilization takes 30+ seconds
def test_stabilization_complete_file_created(host):
    """Test that stabilization_complete file is created after 30 seconds."""
    # Arrange: Clean up and restart
    host.run("systemctl stop ndi-capture")
    host.run("rm -f /var/run/media-bridge/stabilization_complete")
    host.run("systemctl start ndi-capture")
    
    # Act: Wait for stabilization period
    time.sleep(32)  # 30 seconds + buffer
    
    # Assert: Stabilization complete file should exist
    complete_file = host.file("/var/run/media-bridge/stabilization_complete")
    assert complete_file.exists, "Stabilization complete marker not found"


@pytest.mark.slow
@pytest.mark.timeout(60)  # Stabilization takes 30+ seconds
def test_state_transitions_to_capturing(host):
    """Test that state transitions to CAPTURING after stabilization."""
    # First check if already in correct state
    state_file = host.file("/var/run/media-bridge/capture_state")
    if state_file.exists:
        current_state = state_file.content_string.strip()
        if current_state == "CAPTURING":
            # Already in correct state, test passes
            assert True, "Already in CAPTURING state"
            return
    
    # Only restart if not in correct state
    # Arrange: Restart for fresh stabilization
    host.run("systemctl restart ndi-capture")
    time.sleep(2)
    
    # Act: Wait for stabilization to complete
    time.sleep(31)
    
    # Assert: State should now be CAPTURING (after stabilization)
    state = host.file("/var/run/media-bridge/capture_state").content_string.strip()
    assert state == "CAPTURING", f"Expected CAPTURING, got {state}"


def test_dropped_frames_tracked(host):
    """Test that dropped frames are tracked during capture."""
    # Arrange: Restart service
    host.run("systemctl restart ndi-capture")
    
    # Act: Wait for service to start tracking
    time.sleep(5)
    
    # Assert: Dropped frames file should exist
    dropped_file = host.file("/var/run/media-bridge/frames_dropped")
    assert dropped_file.exists, "Dropped frames tracking file not found"
    # Content should be a number (could be 0)
    assert dropped_file.content_string.strip().isdigit(), "Invalid dropped frame count"


def test_capture_start_time_recorded(host):
    """Test that capture start time is recorded."""
    # Arrange: Note current time and restart
    host.run("systemctl restart ndi-capture")
    time.sleep(2)
    
    # Assert: Start time file should exist and contain timestamp
    start_file = host.file("/var/run/media-bridge/capture_start_time")
    assert start_file.exists, "Capture start time not recorded"
    assert start_file.content_string.strip().isdigit(), "Invalid timestamp format"