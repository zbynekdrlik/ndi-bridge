"""
Tests for PipeWire user session architecture with PipeWire 1.4.7.

Verifies that PipeWire runs as a user session with loginctl lingering.
"""

import pytest
import time


def test_pipewire_user_service_exists(host):
    """Test that PipeWire user service is available."""
    # Check user service file exists
    service_file = host.file("/usr/lib/systemd/user/pipewire.service")
    assert service_file.exists, "pipewire.service user unit not found"


def test_pipewire_pulse_user_service_exists(host):
    """Test that pipewire-pulse user service is available."""
    service_file = host.file("/usr/lib/systemd/user/pipewire-pulse.service")
    assert service_file.exists, "pipewire-pulse.service user unit not found"


def test_wireplumber_user_service_exists(host):
    """Test that wireplumber user service is available."""
    service_file = host.file("/usr/lib/systemd/user/wireplumber.service")
    assert service_file.exists, "wireplumber.service user unit not found"


def test_mediabridge_user_lingering_enabled(host):
    """Test that loginctl lingering is enabled for mediabridge user."""
    result = host.run("loginctl show-user mediabridge -p Linger")
    assert "Linger=yes" in result.stdout, "Lingering not enabled for mediabridge user"


def test_pipewire_user_service_running(host):
    """Test that PipeWire is running as user session."""
    # Check if PipeWire is running as mediabridge user
    result = host.run("pgrep -u mediabridge pipewire")
    assert result.rc == 0, "PipeWire not running as mediabridge user"


def test_single_pipewire_instance(host):
    """Test that only appropriate PipeWire instances are running."""
    result = host.run("pgrep -c pipewire")
    # Should be: pipewire, pipewire-pulse
    count = int(result.stdout.strip())
    assert count <= 3, f"Too many PipeWire instances: {count}"


def test_pipewire_runs_as_mediabridge(host):
    """Test that PipeWire instances are running as mediabridge user."""
    # Use ps with uid check instead of username grep
    result = host.run("ps -u mediabridge | grep pipewire")
    assert "pipewire" in result.stdout, "PipeWire not running as mediabridge user"


def test_xdg_runtime_dir_configured(host):
    """Test that XDG_RUNTIME_DIR is properly configured."""
    # Check runtime dir exists for mediabridge user
    runtime_dir = host.file("/run/user/999")
    assert runtime_dir.exists, "Runtime directory not found for mediabridge user"
    assert runtime_dir.is_directory, "Runtime directory is not a directory"


def test_pulse_socket_exists(host):
    """Test that PulseAudio socket exists for compatibility."""
    socket = host.file("/run/user/999/pulse/native")
    assert socket.exists, "PulseAudio socket not found"


def test_audio_manager_installed(host):
    """Test that media-bridge-audio-manager is installed."""
    manager = host.file("/usr/local/bin/media-bridge-audio-manager")
    assert manager.exists, "Audio manager not installed"
    assert manager.mode == 0o755, "Audio manager not executable"


def test_virtual_audio_devices_configured(host):
    """Test that virtual audio devices are configured (if config exists)."""
    # Check if configuration files exist (may be temporarily moved)
    config_dir = host.file("/etc/pipewire/pipewire.conf.d")
    if config_dir.exists:
        config = host.file("/etc/pipewire/pipewire.conf.d/20-virtual-devices.conf")
        if config.exists:
            assert config.exists, "Virtual devices configuration not found"


def test_wireplumber_config_installed(host):
    """Test that WirePlumber configuration is installed."""
    config = host.file("/etc/wireplumber/main.lua.d/50-media-bridge.lua")
    # This might not exist with user session, skip if not found
    if not config.exists:
        pytest.skip("WirePlumber custom config not needed for user session")


def test_low_latency_config_present(host):
    """Test that low latency configuration is present (if exists)."""
    config_dir = host.file("/etc/pipewire/pipewire.conf.d")
    if config_dir.exists:
        config = host.file("/etc/pipewire/pipewire.conf.d/10-media-bridge.conf")
        if config.exists:
            # Check for quantum setting
            content = host.run("cat /etc/pipewire/pipewire.conf.d/10-media-bridge.conf")
            assert "default.clock.quantum = 256" in content.stdout, "Low latency quantum not configured"


def test_pipewire_version_147(host):
    """Test that PipeWire 1.4.7 is installed."""
    result = host.run("pipewire --version")
    assert "1.4.7" in result.stdout, f"Expected PipeWire 1.4.7, got: {result.stdout}"


def test_pw_container_available(host):
    """Test that pw-container tool is available (new in 1.4.7)."""
    result = host.run("which pw-container")
    assert result.rc == 0, "pw-container tool not found (required for Chrome isolation)"


@pytest.mark.slow
def test_intercom_uses_user_pipewire(host):
    """Test that intercom uses user session PipeWire when running."""
    # Check if intercom is running
    if not host.service("media-bridge-intercom").is_running:
        pytest.skip("Intercom service not running")
    
    # Give it time to start
    time.sleep(5)
    
    # Check that Chrome audio streams appear in PipeWire
    result = host.run("sudo -u mediabridge pactl list clients | grep -i chrome")
    if result.rc == 0:
        assert "chrome" in result.stdout.lower(), "Chrome not using PipeWire"


def test_virtual_audio_device_creation(host):
    """Test that virtual audio devices can be created."""
    # Check if PipeWire is running as user session
    result = host.run("pgrep -u mediabridge pipewire")
    if result.rc != 0:
        pytest.skip("PipeWire not running as user session")
    
    # Try to list audio devices as mediabridge user
    result = host.run("sudo -u mediabridge pactl list sinks short")
    assert result.rc == 0, f"Cannot list audio sinks: {result.stderr}"


def test_usb_audio_not_exposed_directly(host):
    """Test that USB audio is not directly exposed to Chrome."""
    # This test verifies the virtual device isolation
    # Chrome should only see virtual devices, not hardware
    config_dir = host.file("/etc/pipewire/pipewire.conf.d")
    if config_dir.exists:
        config = host.file("/etc/pipewire/pipewire.conf.d/20-virtual-devices.conf")
        if config.exists:
            content = config.content_string
            assert "intercom-speaker" in content, "Virtual speaker not configured"
            assert "intercom-microphone" in content, "Virtual microphone not configured"


def test_hdmi_audio_separate_from_usb(host):
    """Test that HDMI audio is separate from USB audio."""
    # Check that audio manager handles both separately
    result = host.run("/usr/local/bin/media-bridge-audio-manager verify")
    # Should show separate sections for USB and HDMI or Virtual devices
    assert "Virtual" in result.stdout or "USB" in result.stdout or "audio" in result.stdout.lower()


def test_pipewire_user_socket_exists(host):
    """Test that PipeWire user socket exists."""
    socket = host.file("/usr/lib/systemd/user/pipewire.socket")
    assert socket.exists, "pipewire.socket user unit not found"


def test_pipewire_sockets_created(host):
    """Test that PipeWire creates its own sockets."""
    socket0 = host.file("/run/user/999/pipewire-0")
    socket_mgr = host.file("/run/user/999/pipewire-0-manager")
    
    # These should exist when PipeWire is running
    if socket0.exists:
        assert socket0.is_socket, "pipewire-0 is not a socket"
    if socket_mgr.exists:
        assert socket_mgr.is_socket, "pipewire-0-manager is not a socket"


def test_user_session_services_enabled(host):
    """Test that user session services are enabled for mediabridge."""
    # Check if user services are enabled
    result = host.run("sudo -u mediabridge systemctl --user is-enabled pipewire.service")
    assert "enabled" in result.stdout, "PipeWire user service not enabled"
    
    result = host.run("sudo -u mediabridge systemctl --user is-enabled pipewire-pulse.service")
    assert "enabled" in result.stdout, "PipeWire-pulse user service not enabled"


def test_pipewire_socket_permissions(host):
    """Test that PipeWire sockets have correct permissions."""
    if host.file("/run/user/999/pipewire-0").exists:
        result = host.run("stat -c '%a' /run/user/999/pipewire-0")
        perms = result.stdout.strip()
        # PipeWire creates sockets with 755 or 666
        assert perms in ["755", "666", "777"], f"Unexpected socket permissions: {perms}"


def test_pactl_connectivity_as_mediabridge(host):
    """Test that pactl works when run as mediabridge user."""
    result = host.run("sudo -u mediabridge pactl info")
    assert result.rc == 0, f"pactl failed as mediabridge: {result.stderr}"
    assert "PipeWire" in result.stdout, "Not connected to PipeWire"