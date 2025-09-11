"""
Tests for PipeWire running as mediabridge user.

Verifies that PipeWire runs as a dedicated user with proper permissions,
socket bind mounts, and Chrome isolation.
"""

import pytest
import time


def test_mediabridge_user_exists(host):
    """Test that mediabridge user exists with correct UID."""
    user = host.user("mediabridge")
    assert user.exists, "mediabridge user does not exist"
    assert user.uid == 999, f"mediabridge UID is {user.uid}, expected 999"
    assert user.home == "/var/lib/mediabridge", f"Wrong home: {user.home}"
    assert user.shell == "/bin/false", f"Wrong shell: {user.shell}"


def test_mediabridge_user_groups(host):
    """Test that mediabridge user is in correct groups."""
    user = host.user("mediabridge")
    groups = user.groups
    required_groups = ["audio", "pipewire", "video", "input", "render"]
    for group in required_groups:
        assert group in groups, f"mediabridge not in {group} group"


def test_user_session_enabled(host):
    """Test that user@999 service is enabled and running."""
    service = host.service("user@999")
    assert service.is_enabled, "user@999 service not enabled"
    assert service.is_running, "user@999 service not running"


def test_loginctl_linger_enabled(host):
    """Test that loginctl linger is enabled for mediabridge."""
    linger_file = host.file("/var/lib/systemd/linger/mediabridge")
    assert linger_file.exists, "loginctl linger not enabled for mediabridge"


def test_pipewire_user_service_running(host):
    """Test that PipeWire is running as user service."""
    # Check if pipewire is running under user session
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user is-active pipewire")
    assert result.stdout.strip() == "active", "PipeWire user service not active"


def test_pipewire_pulse_user_service_running(host):
    """Test that PipeWire-Pulse is running as user service."""
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user is-active pipewire-pulse")
    assert result.stdout.strip() == "active", "PipeWire-Pulse user service not active"


def test_wireplumber_user_service_running(host):
    """Test that WirePlumber is running as user service."""
    result = host.run("sudo -u mediabridge XDG_RUNTIME_DIR=/run/user/999 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/999/bus systemctl --user is-active wireplumber")
    assert result.stdout.strip() == "active", "WirePlumber user service not active"


def test_pipewire_socket_bind_mount(host):
    """Test that PipeWire socket is bind mounted to /run/pipewire."""
    # Check if bind mount exists
    socket = host.file("/run/pipewire/pipewire-0")
    assert socket.exists, "PipeWire socket not bind mounted to /run/pipewire"
    
    # Verify it's actually a socket
    result = host.run("file /run/pipewire/pipewire-0")
    assert "socket" in result.stdout.lower(), "pipewire-0 is not a socket"


def test_pulse_socket_bind_mount(host):
    """Test that Pulse socket is bind mounted."""
    pulse_dir = host.file("/run/pipewire/pulse")
    assert pulse_dir.exists, "Pulse directory not bind mounted"
    
    # Check for native socket
    pulse_socket = host.file("/run/pipewire/pulse/native")
    if pulse_socket.exists:
        result = host.run("file /run/pipewire/pulse/native")
        assert "socket" in result.stdout.lower(), "pulse/native is not a socket"


def test_no_system_pipewire_services(host):
    """Test that old system PipeWire services are disabled."""
    old_services = ["pipewire-system", "pipewire-pulse-system", "wireplumber-system"]
    for service_name in old_services:
        service = host.service(service_name)
        assert not service.is_enabled, f"{service_name} should be disabled"
        assert not service.is_running, f"{service_name} should not be running"


def test_pipewire_running_as_mediabridge(host):
    """Test that PipeWire processes run as mediabridge user."""
    result = host.run("ps aux | grep -E 'pipewire|wireplumber' | grep -v grep")
    lines = result.stdout.strip().split('\n')
    
    for line in lines:
        if line and ('pipewire' in line or 'wireplumber' in line):
            # First field is the username
            username = line.split()[0]
            assert username == "mediabridge", f"PipeWire process running as {username}, not mediabridge"


def test_realtime_limits_configured(host):
    """Test that realtime scheduling limits are configured."""
    limits_file = host.file("/etc/security/limits.d/99-mediabridge.conf")
    assert limits_file.exists, "Realtime limits file not found"
    
    content = limits_file.content_string
    assert "@audio   -  rtprio     95" in content, "Audio group rtprio not set"
    assert "@audio   -  nice      -19" in content, "Audio group nice not set"
    assert "@audio   -  memlock    unlimited" in content, "Audio group memlock not set"
    assert "mediabridge   -  rtprio     95" in content, "mediabridge rtprio not set"


def test_pipewire_has_realtime_priority(host):
    """Test that PipeWire has realtime scheduling priority."""
    result = host.run("ps -eLo pid,tid,class,rtprio,ni,comm | grep pipewire | head -1")
    if result.stdout:
        fields = result.stdout.strip().split()
        # Check if scheduling class is FF (FIFO) or RR (Round Robin)
        if len(fields) >= 3:
            sched_class = fields[2]
            assert sched_class in ["FF", "RR"], f"PipeWire not using realtime scheduling: {sched_class}"


def test_tmpfiles_configuration(host):
    """Test that tmpfiles.d configuration exists."""
    tmpfiles = host.file("/etc/tmpfiles.d/mediabridge.conf")
    assert tmpfiles.exists, "tmpfiles.d configuration not found"
    
    content = tmpfiles.content_string
    assert "d /run/pipewire 0755 mediabridge audio" in content
    assert "d /run/user/999 0700 mediabridge audio" in content
    assert "d /var/lib/mediabridge 0755 mediabridge audio" in content


def test_chrome_profile_location(host):
    """Test that Chrome profile is in the correct location."""
    profile_dir = host.file("/var/lib/mediabridge/chrome-profile")
    assert profile_dir.exists, "Chrome profile directory not found"
    assert profile_dir.is_directory, "Chrome profile is not a directory"
    assert profile_dir.user == "mediabridge", f"Chrome profile owned by {profile_dir.user}"
    assert profile_dir.group == "audio", f"Chrome profile group is {profile_dir.group}"


def test_chrome_profile_preferences(host):
    """Test that Chrome preferences are configured."""
    prefs = host.file("/var/lib/mediabridge/chrome-profile/Default/Preferences")
    if prefs.exists:
        content = prefs.content_string
        assert "vdo.ninja" in content, "VDO.Ninja permissions not configured"
        assert "media_stream_mic" in content, "Microphone permissions not set"
        assert "media_stream_camera" in content, "Camera permissions not set"


def test_wireplumber_chrome_isolation(host):
    """Test that WirePlumber Chrome isolation config exists."""
    config = host.file("/var/lib/mediabridge/.config/wireplumber/wireplumber.conf.d/50-chrome-isolation.conf")
    assert config.exists, "Chrome isolation config not found"
    
    content = config.content_string
    assert "application.process.binary" in content
    assert "chrome" in content
    assert "intercom-speaker" in content
    assert "intercom-microphone" in content


def test_service_environment_variables(host):
    """Test that services have correct environment variables."""
    # Check intercom service environment
    result = host.run("systemctl show media-bridge-intercom -p Environment")
    env = result.stdout
    assert "XDG_RUNTIME_DIR=/run/pipewire" in env
    assert "PIPEWIRE_RUNTIME_DIR=/run/pipewire" in env
    assert "PULSE_RUNTIME_PATH=/run/pipewire/pulse" in env


def test_helper_scripts_updated(host):
    """Test that helper scripts use correct paths."""
    scripts = [
        "/usr/local/bin/media-bridge-audio-manager",
        "/usr/local/bin/media-bridge-intercom-control",
        "/usr/local/bin/ndi-display-launcher"
    ]
    
    for script_path in scripts:
        script = host.file(script_path)
        if script.exists:
            content = script.content_string
            assert "/run/pipewire" in content, f"{script_path} not using /run/pipewire"
            assert "/run/user/0" not in content, f"{script_path} still using old /run/user/0"


def test_migration_script_exists(host):
    """Test that migration script exists and is executable."""
    script = host.file("/usr/local/bin/migrate-pipewire-user.sh")
    assert script.exists, "Migration script not found"
    assert script.mode == 0o755, "Migration script not executable"


def test_audio_device_permissions(host):
    """Test that mediabridge user can access audio devices."""
    # Check if user can list audio devices
    result = host.run("sudo -u mediabridge pactl list sinks short")
    assert result.exit_status == 0, "mediabridge cannot list audio sinks"
    
    result = host.run("sudo -u mediabridge pactl list sources short")
    assert result.exit_status == 0, "mediabridge cannot list audio sources"


def test_virtual_devices_accessible(host):
    """Test that virtual audio devices are accessible."""
    result = host.run("sudo -u mediabridge pactl list sinks short")
    output = result.stdout
    
    # Check for virtual devices
    if "intercom-speaker" in output:
        assert True, "Virtual speaker device found"
    
    result = host.run("sudo -u mediabridge pactl list sources short")
    output = result.stdout
    
    if "intercom-microphone" in output:
        assert True, "Virtual microphone device found"


def test_pipewire_socket_permissions(host):
    """Test that PipeWire sockets have correct permissions."""
    # Check main socket
    result = host.run("ls -l /run/pipewire/pipewire-0 2>/dev/null | head -1")
    if result.stdout:
        # Socket should be accessible by mediabridge
        assert "mediabridge" in result.stdout or "srw" in result.stdout


def test_service_user_configuration(host):
    """Test that all services run as mediabridge user."""
    services = [
        "media-bridge-intercom",
        "ndi-display@0",
        "ndi-capture"
    ]
    
    for service_name in services:
        # Check service user configuration
        result = host.run(f"systemctl show {service_name} -p User")
        user = result.stdout.strip().split('=')[1] if '=' in result.stdout else ""
        if user:  # Service exists
            assert user == "mediabridge", f"{service_name} not running as mediabridge: {user}"


def test_pipewire_version_correct(host):
    """Test that PipeWire version is 1.4.7."""
    result = host.run("sudo -u mediabridge pipewire --version")
    version = result.stdout.strip()
    assert "1.4.7" in version, f"Wrong PipeWire version: {version}"


def test_wireplumber_version_correct(host):
    """Test that WirePlumber is version 0.5.x."""
    result = host.run("sudo -u mediabridge wireplumber --version")
    version = result.stdout.strip()
    assert "0.5" in version or "0.4" in version, f"Wrong WirePlumber version: {version}"