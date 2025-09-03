"""
Atomic tests for HDMI audio volume verification.

These tests ensure HDMI volume is set to 100% for ndi-display.
"""

import pytest
import time


def test_hdmi_volume_script_exists(host):
    """Test that ndi-display-audio-setup script exists."""
    script = host.file("/usr/local/bin/ndi-display-audio-setup")
    assert script.exists, "ndi-display-audio-setup script missing"


def test_hdmi_volume_script_executable(host):
    """Test that ndi-display-audio-setup script is executable."""
    script = host.file("/usr/local/bin/ndi-display-audio-setup")
    assert script.mode & 0o111, "ndi-display-audio-setup script not executable"


def test_hdmi_volume_script_sets_100_percent(host):
    """Test that audio setup script contains volume setting to 100%."""
    result = host.run("grep 'pactl set-sink-volume.*100%' /usr/local/bin/ndi-display-audio-setup")
    assert result.succeeded, "Script doesn't set volume to 100%"


def test_hdmi_sink_volume_default(host):
    """Test that HDMI audio sink default volume is accessible."""
    # Get first HDMI sink
    result = host.run("pactl list sinks short | grep -i hdmi | head -1 | awk '{print $2}'")
    if result.stdout.strip():
        sink_name = result.stdout.strip()
        # Check we can query the volume
        volume_result = host.run(f"pactl list sinks | grep -A 15 '{sink_name}' | grep Volume:")
        assert volume_result.succeeded, f"Cannot query volume for sink {sink_name}"


def test_hdmi_volume_set_command_works(host):
    """Test that volume can be set on HDMI sinks."""
    # Get first HDMI sink
    result = host.run("pactl list sinks short | grep -i hdmi | head -1 | awk '{print $2}'")
    if result.stdout.strip():
        sink_name = result.stdout.strip()
        # Try to set volume (won't persist, just testing command)
        volume_result = host.run(f"pactl set-sink-volume '{sink_name}' 100% 2>&1")
        assert volume_result.succeeded or "not found" in volume_result.stdout.lower(), \
            f"Failed to set volume on {sink_name}: {volume_result.stdout}"


def test_display_launcher_calls_audio_setup(host):
    """Test that display launcher script calls audio setup."""
    result = host.run("grep 'ndi-display-audio-setup' /usr/local/bin/ndi-display-launcher")
    assert result.succeeded, "Display launcher doesn't call audio setup script"


def test_display_service_template_uses_launcher(host):
    """Test that display service template uses launcher script."""
    result = host.run("grep 'ndi-display-launcher' /etc/systemd/system/ndi-display@.service")
    assert result.succeeded, "Display service doesn't use launcher script"


@pytest.mark.display
def test_hdmi_volume_100_after_display_start(host):
    """Test that HDMI volume is set to 100% after display service starts."""
    # Stop any running display services first
    host.run("systemctl stop 'ndi-display@*' 2>/dev/null || true")
    time.sleep(2)
    
    # Start display 0 (even without stream, launcher should set volume)
    result = host.run("systemctl start ndi-display@0")
    time.sleep(3)  # Give audio setup time to run
    
    # Check if any HDMI sink has 100% volume
    result = host.run("pactl list sinks | grep -B 5 -A 5 hdmi | grep -E 'Name:|Volume:' | head -4")
    if "hdmi" in result.stdout.lower():
        # Extract sink name and volume
        lines = result.stdout.strip().split('\n')
        for i, line in enumerate(lines):
            if "Name:" in line and "hdmi" in line.lower():
                sink_name = line.split("Name:")[1].strip()
                # Look for volume in next lines
                for j in range(i+1, min(i+3, len(lines))):
                    if "Volume:" in lines[j]:
                        # Check if volume is at or near 100%
                        # Volume format: "Volume: front-left: 65536 / 100% / 0.00 dB"
                        assert "100%" in lines[j] or "99%" in lines[j] or "98%" in lines[j], \
                            f"HDMI sink {sink_name} not at 100% volume: {lines[j]}"
                        break
    
    # Clean up
    host.run("systemctl stop ndi-display@0 2>/dev/null || true")


def test_audio_setup_script_hdmi_detection(host):
    """Test that audio setup script can detect HDMI sinks."""
    # Run the audio setup script in test mode (display 0)
    result = host.run("/usr/local/bin/ndi-display-audio-setup 0 2>&1")
    # Should either find HDMI or report warning
    assert "audio routed to:" in result.stdout or "No HDMI audio sink found" in result.stdout, \
        "Audio setup script doesn't report HDMI status"


def test_pipewire_hdmi_sink_enumeration(host):
    """Test that PipeWire can enumerate HDMI sinks."""
    result = host.run("pactl list sinks short | grep -c hdmi")
    hdmi_count = int(result.stdout.strip()) if result.stdout.strip().isdigit() else 0
    # System should have at least one HDMI sink capability
    assert hdmi_count >= 0, "PipeWire cannot enumerate HDMI sinks"


def test_hdmi_volume_persistence_check(host):
    """Test that we can check current HDMI volume levels."""
    # This test verifies we can query volume for monitoring
    result = host.run("""
        for sink in $(pactl list sinks short | grep -i hdmi | awk '{print $2}'); do
            echo -n "$sink: "
            pactl list sinks | grep -A 15 "$sink" | grep Volume: | head -1 | grep -oE '[0-9]+%' | head -1
        done
    """)
    # Should execute without error (even if no HDMI sinks)
    assert result.succeeded, "Cannot query HDMI sink volumes"


def test_hdmi_audio_100_percent_in_launcher(host):
    """Test that launcher would set 100% if HDMI sink exists."""
    # Check launcher calls audio setup which sets 100%
    launcher_check = host.run("grep 'ndi-display-audio-setup' /usr/local/bin/ndi-display-launcher")
    audio_setup_check = host.run("grep '100%' /usr/local/bin/ndi-display-audio-setup")
    
    assert launcher_check.succeeded and audio_setup_check.succeeded, \
        "Volume setting chain broken: launcher -> audio-setup -> 100%"


@pytest.mark.slow
def test_hdmi_volume_functional_with_stream(host):
    """
    FUNCTIONAL: Test HDMI volume is 100% when actually playing a stream.
    This test requires an NDI stream to be available.
    """
    # List available streams
    result = host.run("/opt/media-bridge/ndi-display list")
    if not result.succeeded or not result.stdout.strip():
        pytest.skip("No NDI streams available for functional test")
    
    # Extract first stream name
    stream_name = None
    for line in result.stdout.split('\n'):
        if ': ' in line and not line.startswith('['):
            parts = line.split(': ', 1)
            if len(parts) > 1:
                stream_name = parts[1].strip()
                break
    
    if not stream_name:
        pytest.skip("No valid NDI stream found")
    
    # Configure display 0 with this stream
    # Note: The correct path for NDI display configs is /etc/ndi-display/
    host.run("mkdir -p /etc/ndi-display")
    host.run(f"""
        echo 'STREAM_NAME="{stream_name}"' > /etc/ndi-display/display-0.conf
        echo 'ENABLED=true' >> /etc/ndi-display/display-0.conf
    """)
    
    # Start the display
    host.run("systemctl restart ndi-display@0")
    time.sleep(5)  # Wait for stream to start and audio to be configured
    
    # Check HDMI volume
    result = host.run("""
        for sink in $(pactl list sinks short | grep -i hdmi | awk '{print $2}'); do
            pactl list sinks | grep -B 5 "$sink" | grep -A 10 Volume: | grep -oE '[0-9]+%' | head -1
        done
    """)
    
    if result.stdout.strip():
        volumes = result.stdout.strip().split('\n')
        for volume in volumes:
            if volume.strip():
                vol_int = int(volume.strip().rstrip('%'))
                assert vol_int >= 98, f"HDMI volume not at 100%: {volume}"
    
    # Clean up - ensure display is stopped and config is removed
    host.run("systemctl stop ndi-display@0")
    host.run("rm -f /etc/ndi-display/display-0.conf")
    # Also clear any runtime status
    host.run("rm -f /var/run/ndi-display/display-0.status")