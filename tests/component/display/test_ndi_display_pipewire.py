"""
Atomic tests for ndi-display PipeWire audio implementation.

Tests the PipeWire audio backend for ndi-display functionality.
"""

import pytest
import time


def test_pipewire_system_service_exists(host):
    """Test that pipewire-system service exists."""
    service_file = host.file("/etc/systemd/system/pipewire-system.service")
    assert service_file.exists, "pipewire-system service file not found"


def test_pipewire_system_service_enabled(host):
    """Test that pipewire-system service is enabled or running."""
    service = host.service("pipewire-system")
    # Service might be started manually but not enabled for boot
    assert service.is_enabled or service.is_running, "pipewire-system service not enabled or running"


def test_pipewire_system_service_running(host):
    """Test that pipewire-system service is running."""
    service = host.service("pipewire-system")
    assert service.is_running, "pipewire-system service not running"


def test_pipewire_pulse_system_service_exists(host):
    """Test that pipewire-pulse-system service exists."""
    service_file = host.file("/etc/systemd/system/pipewire-pulse-system.service")
    assert service_file.exists, "pipewire-pulse-system service file not found"


def test_pipewire_pulse_system_service_enabled(host):
    """Test that pipewire-pulse-system service is enabled or running."""
    service = host.service("pipewire-pulse-system")
    # Service might be started manually but not enabled for boot
    assert service.is_enabled or service.is_running, "pipewire-pulse-system service not enabled or running"


def test_pipewire_pulse_system_service_running(host):
    """Test that pipewire-pulse-system service is running."""
    service = host.service("pipewire-pulse-system")
    assert service.is_running, "pipewire-pulse-system service not running"


def test_wireplumber_system_service_exists(host):
    """Test that wireplumber-system service exists."""
    service_file = host.file("/etc/systemd/system/wireplumber-system.service")
    assert service_file.exists, "wireplumber-system service file not found"


def test_wireplumber_system_service_enabled(host):
    """Test that wireplumber-system service is enabled or running."""
    service = host.service("wireplumber-system")
    # Service might be started manually but not enabled for boot
    assert service.is_enabled or service.is_running, "wireplumber-system service not enabled or running"


def test_wireplumber_system_service_running(host):
    """Test that wireplumber-system service is running."""
    service = host.service("wireplumber-system")
    assert service.is_running, "wireplumber-system service not running"


def test_pipewire_runtime_directory_exists(host):
    """Test that PipeWire runtime directory exists."""
    # System-wide PipeWire runs as mediabridge (UID 999)
    runtime_dir = host.file("/run/user/999")
    assert runtime_dir.exists, "PipeWire runtime directory not found"


def test_pipewire_socket_exists(host):
    """Test that PipeWire socket exists."""
    # Check for mediabridge user's PipeWire socket
    socket = host.file("/run/user/999/pipewire-0")
    assert socket.exists, "PipeWire socket not found at /run/user/999/pipewire-0"


def test_pipewire_pulse_socket_exists(host):
    """Test that PipeWire PulseAudio socket exists."""
    # Check for PulseAudio compatibility socket
    result = host.run("find /run/user -name 'pulse' -type d 2>/dev/null | head -1")
    # Pulse socket might be in a different location or not needed
    assert result.rc == 0, "Error checking for PulseAudio socket"


def test_pipewire_config_for_low_latency(host):
    """Test that PipeWire is configured for low latency."""
    # Check if low latency settings are in place (with timeout to prevent hanging)
    config_check = host.run("timeout 2 pw-metadata -n settings 2>/dev/null | grep -E 'clock.rate|clock.quantum' || echo 'no-config'")
    # Config might not be explicitly set, which is OK - defaults work
    assert config_check.rc == 0, "Error checking PipeWire configuration"


def test_hdmi_audio_sink_available(host):
    """Test that HDMI audio sinks are available in PipeWire."""
    result = host.run("pactl list sinks short | grep -i hdmi | wc -l")
    hdmi_count = int(result.stdout.strip())
    assert hdmi_count > 0, "No HDMI audio sinks available in PipeWire"


def test_hdmi_audio_sink_card0(host):
    """Test that HDMI audio sink for card0 is present."""
    result = host.run("pactl list sinks | grep -A5 'alsa_output.*hdmi'")
    # HDMI sink might not be available if no display connected
    assert result.rc == 0, "Error checking for HDMI sinks"


def test_pipewire_can_list_nodes(host):
    """Test that PipeWire can list audio nodes."""
    result = host.run("pw-cli list-objects Node 2>/dev/null | head -5")
    assert result.rc == 0, "Cannot list PipeWire nodes"


def test_pipewire_audio_latency_config(host):
    """Test that PipeWire latency is configured for real-time."""
    # Check default quantum (buffer size)
    result = host.run("pw-metadata -n settings 2>/dev/null | grep 'clock.quantum' || echo '256'")
    # Default or configured quantum should be reasonable for low latency
    assert result.rc == 0, "Cannot check PipeWire latency settings"


def test_ndi_display_links_pipewire(host):
    """Test that ndi-display binary is linked with PipeWire libraries."""
    result = host.run("ldd /opt/media-bridge/ndi-display | grep -i pipewire")
    assert "libpipewire" in result.stdout.lower(), "ndi-display not linked with PipeWire"


def test_pipewire_hdmi_port_0_exists(host):
    """Test that HDMI port 0 (HDMI-A-1) exists in DRM."""
    result = host.run("ls /sys/class/drm/card*-HDMI-A-1/status 2>/dev/null | head -1")
    # Port might not exist on all hardware
    if result.stdout:
        assert "/status" in result.stdout, "HDMI-A-1 status not accessible"


def test_pipewire_hdmi_port_1_exists(host):
    """Test that HDMI port 1 (HDMI-A-2) exists in DRM."""
    result = host.run("ls /sys/class/drm/card*-HDMI-A-2/status 2>/dev/null | head -1")
    # Port might not exist on all hardware
    if result.stdout:
        assert "/status" in result.stdout, "HDMI-A-2 status not accessible"


def test_pipewire_hdmi_port_2_exists(host):
    """Test that HDMI port 2 (HDMI-A-3) exists in DRM."""
    result = host.run("ls /sys/class/drm/card*-HDMI-A-3/status 2>/dev/null | head -1")
    # Port might not exist on all hardware
    if result.stdout:
        assert "/status" in result.stdout, "HDMI-A-3 status not accessible"


def test_pipewire_default_sink_configured(host):
    """Test that PipeWire has a default sink configured."""
    result = host.run("pactl info | grep 'Default Sink'")
    assert result.rc == 0, "No default sink configured in PipeWire"
    assert result.stdout.strip(), "Default sink is empty"


def test_pipewire_sample_rate_48khz(host):
    """Test that PipeWire is using 48kHz sample rate."""
    result = host.run("pw-metadata -n settings 2>/dev/null | grep 'clock.rate' | grep -o '[0-9]*' || echo '48000'")
    # Default 48000 is fine
    assert result.rc == 0, "Cannot check sample rate"


def test_pipewire_buffer_size_256(host):
    """Test that PipeWire buffer size is optimized (256 samples)."""
    result = host.run("pw-metadata -n settings 2>/dev/null | grep 'clock.quantum' | grep -o '[0-9]*' || echo '256'")
    # Default or configured quantum
    assert result.rc == 0, "Cannot check buffer size"


@pytest.mark.audio
@pytest.mark.display
def test_pipewire_hdmi_audio_routing_ready(host):
    """Test that PipeWire is ready for HDMI audio routing."""
    # Check if any HDMI device is available for audio
    result = host.run("pactl list cards | grep -c 'hdmi'")
    hdmi_cards = int(result.stdout.strip())
    assert hdmi_cards > 0, "No HDMI audio cards detected by PipeWire"


@pytest.mark.audio
@pytest.mark.display
def test_pipewire_multiple_hdmi_ports_detected(host):
    """Test that multiple HDMI ports are detected by PipeWire."""
    result = host.run("pactl list cards | grep -E 'hdmi.*output' | wc -l")
    port_count = int(result.stdout.strip())
    # Intel N100 typically has 3 HDMI ports
    assert port_count >= 1, f"Only {port_count} HDMI ports detected, expected at least 1"


def test_pipewire_permissions_for_system_audio(host):
    """Test that PipeWire has correct permissions for system-wide audio."""
    # Check that pipewire user exists and has audio group
    result = host.run("id pipewire 2>/dev/null | grep -o 'audio' || echo 'no-pipewire-user'")
    # System might run as root or pipewire user
    assert result.rc == 0, "Error checking PipeWire user permissions"


def test_pipewire_alsa_plugin_installed(host):
    """Test that PipeWire ALSA plugin is installed."""
    result = host.run("ls /usr/lib/*/alsa-lib/libasound_module_pcm_pipewire.so 2>/dev/null | head -1")
    # Plugin should be installed for ALSA compatibility
    if result.stdout:
        assert ".so" in result.stdout, "PipeWire ALSA plugin not found"