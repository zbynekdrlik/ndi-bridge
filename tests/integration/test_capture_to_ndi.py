"""
Integration test for capture to NDI transmission.

Tests the interaction between capture device and NDI sender.
"""

import pytest
import time


def test_capture_to_ndi_pipeline_active(host):
    """Test that capture to NDI pipeline is functioning."""
    # Verify capture is running
    capture_service = host.service("ndi-capture")
    assert capture_service.is_running, "Capture service not running"
    
    # Wait for stabilization if needed
    state = host.file("/var/run/ndi-bridge/capture_state").content_string.strip()
    if state == "STABILIZING":
        time.sleep(30)
    
    # Check NDI sender is active (look for NDI process/thread)
    ndi_active = host.run("pgrep -f ndi-capture")
    assert ndi_active.succeeded, "NDI capture process not found"
    
    # Verify frames are being captured
    frames1 = int(host.file("/var/run/ndi-bridge/frames_captured").content_string.strip())
    time.sleep(2)
    frames2 = int(host.file("/var/run/ndi-bridge/frames_captured").content_string.strip())
    
    assert frames2 > frames1, "Frames not being captured"


@pytest.mark.integration
def test_ndi_stream_discoverable(host):
    """Test that NDI stream is discoverable on network."""
    # Get device NDI name
    ndi_name_file = host.file("/etc/media-bridge-name")
    if ndi_name_file.exists:
        ndi_name = ndi_name_file.content_string.strip()
    else:
        # Fallback to hostname
        ndi_name = host.run("hostname").stdout.strip()
    
    # Check if NDI tools can find the stream (if ndi-find is available)
    result = host.run("which ndi-find")
    if result.succeeded:
        find_result = host.run("timeout 5 ndi-find")
        assert ndi_name in find_result.stdout, f"NDI stream '{ndi_name}' not found"


def test_capture_metadata_in_stream(host):
    """Test that capture metadata is included in NDI stream."""
    # Check if NDI is sending metadata
    # This would require NDI monitoring tools
    
    # For now, verify that capture is generating metadata
    fps = float(host.file("/var/run/ndi-bridge/fps").content_string.strip())
    assert fps > 0, "No FPS metadata available"
    
    # Verify capture resolution is detected
    v4l2_result = host.run("v4l2-ctl --device=/dev/video0 --get-fmt-video | grep Width")
    assert v4l2_result.succeeded, "Cannot read video format"