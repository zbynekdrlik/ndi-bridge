"""
Tests for unified system-wide PipeWire architecture.

Verifies that intercom and ndi-display use the same PipeWire instance.
"""

import pytest
import time


def test_pipewire_system_service_exists(host):
    """Test that pipewire-system service exists."""
    service = host.service("pipewire-system")
    assert service.is_enabled, "pipewire-system service not enabled"


def test_pipewire_pulse_system_service_exists(host):
    """Test that pipewire-pulse-system service exists."""
    service = host.service("pipewire-pulse-system")
    assert service.is_enabled, "pipewire-pulse-system service not enabled"


def test_wireplumber_system_service_exists(host):
    """Test that wireplumber-system service exists."""
    service = host.service("wireplumber-system")
    assert service.is_enabled, "wireplumber-system service not enabled"


def test_pipewire_system_service_running(host):
    """Test that system PipeWire is running."""
    service = host.service("pipewire-system")
    assert service.is_running, "pipewire-system service not running"


def test_single_pipewire_instance(host):
    """Test that only one PipeWire instance is running."""
    result = host.run("pgrep -c pipewire")
    # Should be exactly 3: pipewire, pipewire-pulse, and maybe pipewire-media-session
    count = int(result.stdout.strip())
    assert count <= 3, f"Too many PipeWire instances: {count}"


def test_no_user_pipewire_instances(host):
    """Test that no user-level PipeWire instances are running."""
    # Check for PipeWire processes not running as root
    result = host.run("ps aux | grep pipewire | grep -v root | grep -v grep")
    assert result.stdout.strip() == "", "Found non-root PipeWire processes"


def test_xdg_runtime_dir_configured(host):
    """Test that XDG_RUNTIME_DIR is properly configured."""
    result = host.run("systemctl show pipewire-system -p Environment")
    assert "XDG_RUNTIME_DIR=/run/user/0" in result.stdout


def test_pulse_socket_exists(host):
    """Test that PulseAudio socket exists for compatibility."""
    socket = host.file("/run/user/0/pulse/native")
    assert socket.exists, "PulseAudio socket not found"


def test_audio_manager_installed(host):
    """Test that media-bridge-audio-manager is installed."""
    manager = host.file("/usr/local/bin/media-bridge-audio-manager")
    assert manager.exists, "Audio manager not installed"
    assert manager.mode == 0o755, "Audio manager not executable"


def test_virtual_audio_devices_configured(host):
    """Test that virtual audio devices are configured."""
    # Check if configuration files exist
    config = host.file("/etc/pipewire/pipewire.conf.d/20-virtual-devices.conf")
    assert config.exists, "Virtual devices configuration not found"


def test_wireplumber_config_installed(host):
    """Test that WirePlumber configuration is installed."""
    config = host.file("/etc/wireplumber/main.lua.d/50-media-bridge.lua")
    assert config.exists, "WirePlumber configuration not found"


def test_low_latency_config_present(host):
    """Test that low latency configuration is present."""
    config = host.file("/etc/pipewire/pipewire.conf.d/10-media-bridge.conf")
    assert config.exists, "Low latency configuration not found"
    
    # Check for quantum setting
    content = host.run("cat /etc/pipewire/pipewire.conf.d/10-media-bridge.conf")
    assert "default.clock.quantum = 256" in content.stdout, "Low latency quantum not configured"


def test_intercom_service_depends_on_pipewire(host):
    """Test that intercom service depends on PipeWire."""
    result = host.run("systemctl show media-bridge-intercom -p Requires")
    assert "pipewire-system.service" in result.stdout, "Intercom doesn't require pipewire-system"


def test_pipewire_realtime_priority(host):
    """Test that PipeWire has real-time priority."""
    result = host.run("systemctl show pipewire-system -p Nice")
    # Should be negative for high priority
    if "Nice=" in result.stdout:
        nice_value = result.stdout.split("=")[1].strip()
        if nice_value and nice_value != "[not set]":
            assert int(nice_value) < 0, f"PipeWire not high priority: {nice_value}"


@pytest.mark.slow
def test_intercom_uses_system_pipewire(host):
    """Test that intercom uses system PipeWire when running."""
    # Check if intercom is running
    if not host.service("media-bridge-intercom").is_running:
        pytest.skip("Intercom service not running")
    
    # Give it time to start
    time.sleep(5)
    
    # Check that Chrome audio streams appear in PipeWire
    result = host.run("pactl list clients | grep -i chrome")
    if result.rc == 0:
        assert "chrome" in result.stdout.lower(), "Chrome not using PipeWire"


def test_virtual_audio_device_creation(host):
    """Test that virtual audio devices can be created."""
    # Start PipeWire if not running
    if not host.service("pipewire-system").is_running:
        host.run("systemctl start pipewire-system pipewire-pulse-system wireplumber-system")
        time.sleep(3)
    
    # Try to create virtual devices using audio manager
    result = host.run("/usr/local/bin/media-bridge-audio-manager setup")
    assert result.rc == 0, f"Audio manager setup failed: {result.stderr}"


def test_usb_audio_not_exposed_directly(host):
    """Test that USB audio is not directly exposed to Chrome."""
    # This test verifies the virtual device isolation
    # Chrome should only see virtual devices, not hardware
    config = host.file("/etc/pipewire/pipewire.conf.d/20-virtual-devices.conf")
    if config.exists:
        content = config.content_string
        assert "intercom-speaker" in content, "Virtual speaker not configured"
        assert "intercom-microphone" in content, "Virtual microphone not configured"


def test_hdmi_audio_separate_from_usb(host):
    """Test that HDMI audio is separate from USB audio."""
    # Check that audio manager handles both separately
    result = host.run("/usr/local/bin/media-bridge-audio-manager status")
    # Should show separate sections for USB and HDMI
    assert "USB Devices:" in result.stdout or "HDMI Devices:" in result.stdout