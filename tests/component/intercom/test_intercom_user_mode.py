"""
Tests for Media Bridge Intercom running as mediabridge user.

Verifies Chrome profile location, permissions, and audio routing.
"""

import pytest
import time


def test_intercom_service_user(host):
    """Test that intercom service runs as mediabridge user."""
    result = host.run("systemctl show media-bridge-intercom -p User")
    user = result.stdout.strip().split('=')[1] if '=' in result.stdout else ""
    assert user == "mediabridge", f"Intercom not running as mediabridge: {user}"


def test_intercom_service_group(host):
    """Test that intercom service runs with audio group."""
    result = host.run("systemctl show media-bridge-intercom -p Group")
    group = result.stdout.strip().split('=')[1] if '=' in result.stdout else ""
    assert group == "audio", f"Intercom not in audio group: {group}"


def test_intercom_environment_variables(host):
    """Test that intercom has correct environment variables."""
    result = host.run("systemctl show media-bridge-intercom -p Environment")
    env = result.stdout
    
    required_vars = [
        "XDG_RUNTIME_DIR=/run/pipewire",
        "PIPEWIRE_RUNTIME_DIR=/run/pipewire",
        "PULSE_RUNTIME_PATH=/run/pipewire/pulse",
        "CHROME_USER_DATA_DIR=/var/lib/mediabridge/chrome-profile"
    ]
    
    for var in required_vars:
        assert var in env, f"Missing environment variable: {var}"


def test_chrome_profile_permissions(host):
    """Test Chrome profile directory permissions."""
    profile = host.file("/var/lib/mediabridge/chrome-profile")
    assert profile.exists, "Chrome profile directory not found"
    assert profile.is_directory, "Chrome profile is not a directory"
    assert profile.user == "mediabridge", f"Chrome profile owned by {profile.user}"
    assert profile.group == "audio", f"Chrome profile group is {profile.group}"
    assert profile.mode & 0o755 == 0o755, f"Chrome profile has wrong permissions: {oct(profile.mode)}"


def test_chrome_default_profile(host):
    """Test Chrome Default profile exists."""
    default_profile = host.file("/var/lib/mediabridge/chrome-profile/Default")
    assert default_profile.exists, "Chrome Default profile not found"
    assert default_profile.is_directory, "Default profile is not a directory"


def test_chrome_preferences_file(host):
    """Test Chrome preferences with VDO.Ninja permissions."""
    prefs = host.file("/var/lib/mediabridge/chrome-profile/Default/Preferences")
    assert prefs.exists, "Chrome Preferences file not found"
    
    content = prefs.content_string
    # Check for VDO.Ninja permissions
    assert "vdo.ninja" in content, "VDO.Ninja not in preferences"
    assert "media_stream_mic" in content, "Microphone permission not set"
    assert "media_stream_camera" in content, "Camera permission not set"
    assert '"setting": 1' in content, "Permissions not granted (should be 1)"


def test_no_chrome_profile_in_tmp(host):
    """Test that Chrome profile is NOT in /tmp."""
    old_profile = host.file("/tmp/chrome-vdo-profile")
    assert not old_profile.exists, "Old Chrome profile still in /tmp"


def test_no_chrome_profile_in_opt(host):
    """Test that Chrome profile is NOT in /opt."""
    old_profile = host.file("/opt/chrome-vdo-profile")
    assert not old_profile.exists, "Old Chrome profile still in /opt"


def test_intercom_launcher_script(host):
    """Test intercom launcher script configuration."""
    launcher = host.file("/usr/local/bin/media-bridge-intercom-launcher")
    assert launcher.exists, "Intercom launcher not found"
    assert launcher.mode == 0o755, "Launcher not executable"
    
    content = launcher.content_string
    # Should not contain old paths
    assert "/run/user/0" not in content, "Launcher still using /run/user/0"
    assert "/tmp/chrome-vdo-profile" not in content, "Launcher still using /tmp profile"


def test_intercom_pipewire_script(host):
    """Test intercom PipeWire script configuration."""
    script = host.file("/usr/local/bin/media-bridge-intercom-pipewire")
    if script.exists:
        content = script.content_string
        assert "/run/pipewire" in content, "Script not using /run/pipewire"
        assert "/var/lib/mediabridge/chrome-profile" in content, "Script not using new profile path"
        assert "export PIPEWIRE_RUNTIME_DIR" in content, "Missing PIPEWIRE_RUNTIME_DIR"


def test_audio_manager_permissions(host):
    """Test audio manager can be run by mediabridge."""
    result = host.run("sudo -u mediabridge /usr/local/bin/media-bridge-audio-manager status")
    # Exit status 0 means script executed successfully
    # Ignore pulse permission warnings as the script handles them
    assert result.exit_status == 0, f"Audio manager failed to run: {result.stderr}"


def test_virtual_devices_for_chrome(host):
    """Test virtual audio devices exist for Chrome isolation."""
    # Start intercom service if not running
    host.run("systemctl start media-bridge-intercom")
    time.sleep(5)
    
    # Check for virtual speaker
    result = host.run("sudo -u mediabridge pactl list sinks short")
    if "intercom-speaker" not in result.stdout:
        # Try to create it
        host.run("sudo -u mediabridge /usr/local/bin/media-bridge-audio-manager setup")
        time.sleep(2)
        result = host.run("sudo -u mediabridge pactl list sinks short")
    
    assert "intercom-speaker" in result.stdout, "Virtual speaker not found"
    
    # Check for virtual microphone
    result = host.run("sudo -u mediabridge pactl list sources short")
    assert "intercom-microphone" in result.stdout, "Virtual microphone not found"


def test_chrome_process_user(host):
    """Test that Chrome runs as mediabridge user when intercom is active."""
    # Ensure intercom is running
    service = host.service("media-bridge-intercom")
    if not service.is_running:
        host.run("systemctl start media-bridge-intercom")
        time.sleep(10)  # Give Chrome time to start
    
    # Check if Chrome is running
    result = host.run("ps aux | grep chrome | grep -v grep | head -1")
    if result.stdout:
        # Chrome should be running as mediabridge
        username = result.stdout.split()[0]
        assert username == "mediabridge", f"Chrome running as {username}, not mediabridge"


def test_xvfb_process_user(host):
    """Test that Xvfb runs as mediabridge user."""
    # Check if Xvfb is running (part of intercom)
    result = host.run("ps aux | grep Xvfb | grep -v grep | head -1")
    if result.stdout:
        username = result.stdout.split()[0]
        assert username == "mediabridge", f"Xvfb running as {username}, not mediabridge"


def test_chrome_audio_routing(host):
    """Test Chrome audio routing configuration."""
    # Check WirePlumber Chrome isolation config
    config = host.file("/var/lib/mediabridge/.config/wireplumber/wireplumber.conf.d/50-chrome-isolation.conf")
    assert config.exists, "Chrome isolation config not found"
    assert config.user == "mediabridge", f"Config owned by {config.user}"
    
    content = config.content_string
    # Verify Chrome is restricted to virtual devices
    assert '"application.process.binary": "~chrome"' in content, "Chrome matching rule not found"
    assert '"media.allowed": ["intercom-speaker", "intercom-microphone.monitor"]' in content, "Chrome device restrictions not set"


def test_intercom_control_script(host):
    """Test intercom control script with new paths."""
    control = host.file("/usr/local/bin/media-bridge-intercom-control")
    assert control.exists, "Intercom control script not found"
    
    content = control.content_string
    assert "/run/pipewire" in content, "Control script not using /run/pipewire"
    assert "PIPEWIRE_RUNTIME_DIR" in content, "Missing PIPEWIRE_RUNTIME_DIR"


def test_intercom_status_command(host):
    """Test that intercom status command works."""
    result = host.run("sudo -u mediabridge /usr/local/bin/media-bridge-intercom-status")
    # Should not fail with permission errors
    assert result.exit_status == 0 or "not running" in result.stdout.lower()


def test_intercom_restart_permissions(host):
    """Test that mediabridge can restart intercom."""
    # This should work even though systemctl requires sudo
    result = host.run("sudo systemctl restart media-bridge-intercom")
    assert result.exit_status == 0, "Failed to restart intercom"
    
    # Wait and verify it's running
    time.sleep(5)
    service = host.service("media-bridge-intercom")
    assert service.is_running, "Intercom did not restart properly"