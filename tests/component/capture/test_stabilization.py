"""
Atomic tests for capture stabilization behavior (Issue #38).

Tests the 30-second stabilization period during capture startup.
"""

import pytest
import time


def test_initial_state_is_stabilizing(host):
    """Test that capture starts in STABILIZING state after restart."""
    # Arrange: Restart service to trigger fresh stabilization
    host.run("systemctl restart ndi-capture")
    time.sleep(2)  # Brief pause for service to start
    
    # Act: Read the capture state
    state_file = host.file("/var/run/media-bridge/capture_state")
    
    # Assert: Should be in STABILIZING state
    assert state_file.exists, "Capture state file not found"
    assert state_file.content_string.strip() == "STABILIZING"


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
def test_state_transitions_to_running(host):
    """Test that state transitions from STABILIZING to RUNNING."""
    # Arrange: Restart for fresh stabilization
    host.run("systemctl restart ndi-capture")
    time.sleep(2)
    
    # Act: Wait for stabilization to complete
    time.sleep(31)
    
    # Assert: State should now be RUNNING
    state = host.file("/var/run/media-bridge/capture_state").content_string.strip()
    assert state == "RUNNING", f"Expected RUNNING, got {state}"


def test_dropped_baseline_recorded(host):
    """Test that dropped frame baseline is recorded during stabilization."""
    # Arrange: Restart service
    host.run("systemctl restart ndi-capture")
    
    # Act: Wait for stabilization to begin
    time.sleep(5)
    
    # Assert: Dropped baseline file should exist
    baseline_file = host.file("/var/run/media-bridge/dropped_baseline")
    assert baseline_file.exists, "Dropped frame baseline not recorded"


def test_capture_start_time_recorded(host):
    """Test that capture start time is recorded."""
    # Arrange: Note current time and restart
    host.run("systemctl restart ndi-capture")
    time.sleep(2)
    
    # Assert: Start time file should exist and contain timestamp
    start_file = host.file("/var/run/media-bridge/capture_start_time")
    assert start_file.exists, "Capture start time not recorded"
    assert start_file.content_string.strip().isdigit(), "Invalid timestamp format"