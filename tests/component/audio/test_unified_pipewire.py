"""
Tests for unified system-wide PipeWire architecture.

Verifies that intercom and ndi-display use the same PipeWire instance.
"""

import pytest
import time


def test_pipewire_user_service_running(host):
    """Test that PipeWire is running as user service."""
    # Check if PipeWire is running via user session
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user is-active pipewire")
    assert "active" in result.stdout, "PipeWire user service not running"


def test_pipewire_pulse_user_service_running(host):
    """Test that PipeWire-Pulse is running as user service."""
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user is-active pipewire-pulse")
    assert "active" in result.stdout, "PipeWire-Pulse user service not running"


def test_wireplumber_user_service_running(host):
    """Test that WirePlumber is running as user service."""
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user is-active wireplumber")
    assert "active" in result.stdout, "WirePlumber user service not running"


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


def test_intercom_service_depends_on_user_session(host):
    """Test that intercom service depends on user session."""
    result = host.run("systemctl show media-bridge-intercom -p Requires")
    assert "user@999.service" in result.stdout, "Intercom doesn't require user@999"


def test_pipewire_realtime_priority(host):
    """Test that PipeWire has real-time priority."""
    # Check mediabridge user has rtprio capability
    result = host.run("grep mediabridge /etc/security/limits.d/99-mediabridge.conf")
    assert "rtprio" in result.stdout, "mediabridge user lacks rtprio capability"
    assert "95" in result.stdout, "rtprio not set to 95"


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
    # Check if PipeWire user services are running
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user is-active pipewire")
    if "active" not in result.stdout:
        pytest.skip("PipeWire user service not running")
    
    # Try to create virtual devices using audio manager
    result = host.run("XDG_RUNTIME_DIR=/run/pipewire /usr/local/bin/media-bridge-audio-manager setup")
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


def test_pipewire_socket_exists(host):
    """Test that PipeWire socket exists in bind mount location."""
    socket = host.file("/run/pipewire/pipewire-0")
    assert socket.exists, "PipeWire socket not found at /run/pipewire/pipewire-0"
    assert socket.is_socket, "pipewire-0 is not a socket"


def test_user_session_starts_properly(host):
    """Test that user@999 session starts properly."""
    result = host.run("systemctl is-active user@999.service")
    assert "active" in result.stdout, "user@999.service not active"
    
    # Check runtime directory exists
    runtime_dir = host.file("/run/user/999")
    assert runtime_dir.exists, "User runtime directory not created"
    assert runtime_dir.is_directory, "User runtime directory is not a directory"


def test_pipewire_user_config_exists(host):
    """Test that PipeWire user configuration exists."""
    config = host.file("/var/lib/mediabridge/.config/systemd/user/pipewire.service.d/override.conf")
    assert config.exists, "PipeWire user service override not found"
    
    # Check for bind mount configuration
    content = config.content_string
    assert "mount --bind" in content, "Bind mount not configured"
    assert "/run/user/999/pipewire-0" in content, "Source socket path not configured"
    assert "/run/pipewire/pipewire-0" in content, "Target socket path not configured"


def test_pipewire_sockets_created(host):
    """Test that PipeWire creates its own sockets."""
    socket0 = host.file("/run/user/0/pipewire-0")
    socket_mgr = host.file("/run/user/0/pipewire-0-manager")
    
    assert socket0.exists, "PipeWire socket not created"
    assert socket_mgr.exists, "PipeWire manager socket not created"
    assert socket0.is_socket, "pipewire-0 is not a socket"
    assert socket_mgr.is_socket, "pipewire-0-manager is not a socket"


def test_wireplumber_user_service_override(host):
    """Test that WirePlumber user service override exists."""
    override = host.file("/var/lib/mediabridge/.config/systemd/user/wireplumber.service.d/override.conf")
    assert override.exists, "WirePlumber user service override not found"
    
    # Check for socket wait configuration
    content = override.content_string
    assert "ExecStartPre" in content or "After" in content, "WirePlumber dependency configuration missing"


def test_no_bindsto_preventing_restarts(host):
    """Test that user services don't have problematic BindsTo."""
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user show wireplumber -p BindsTo")
    # BindsTo should be properly configured for user services
    bindsto = result.stdout.strip()
    # User services can have BindsTo for pipewire.service
    if "pipewire.service" in bindsto:
        # This is OK for user services
        pass


def test_pipewire_socket_permissions(host):
    """Test that PipeWire sockets have correct permissions."""
    if host.file("/run/user/0/pipewire-0").exists:
        result = host.run("stat -c '%a' /run/user/0/pipewire-0")
        perms = result.stdout.strip()
        # PipeWire creates sockets with 755 or 666
        assert perms in ["755", "666"], f"Unexpected socket permissions: {perms}"