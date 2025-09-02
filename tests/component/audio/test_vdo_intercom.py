"""
Basic compatibility tests for VDO.Ninja intercom components.

This file contains legacy tests updated to work with current implementation.
Most comprehensive tests are in tests/component/intercom/ directory.
"""

import pytest


def test_chrome_or_chromium_installed(host):
    """Test that Chrome is installed (Chromium not supported)."""
    chrome_result = host.run("which google-chrome")
    assert chrome_result.rc == 0, "Google Chrome should be installed"


def test_chrome_executable(host):
    """Test that Chrome binary is executable."""
    chrome_result = host.run("which google-chrome")
    assert chrome_result.rc == 0, "Chrome should be found"
    
    chrome_path = chrome_result.stdout.strip()
    chrome_file = host.file(chrome_path)
    assert chrome_file.mode & 0o111, "Chrome should be executable"


def test_intercom_launcher_script_exists(host):
    """Test that intercom launcher script exists."""
    # Check for actual launcher script
    launcher = host.file("/usr/local/bin/ndi-bridge-intercom-launcher")
    assert launcher.exists, "Intercom launcher script should exist"
    assert launcher.mode & 0o111, "Launcher should be executable"


def test_intercom_service_exists(host):
    """Test that intercom service exists."""
    result = host.run("systemctl list-unit-files | grep ndi-bridge-intercom.service")
    assert result.rc == 0, "ndi-bridge-intercom.service should exist"


def test_pipewire_for_audio_routing(host):
    """Test that PipeWire is available for audio routing."""
    result = host.run("which pipewire")
    assert result.rc == 0, "PipeWire should be installed"


def test_wireplumber_installed(host):
    """Test that WirePlumber is installed for PipeWire."""
    result = host.run("which wireplumber")
    assert result.rc == 0, "WirePlumber should be installed"


def test_pipewire_pulse_compatibility(host):
    """Test that PipeWire PulseAudio compatibility is available."""
    result = host.run("which pipewire-pulse")
    assert result.rc == 0, "pipewire-pulse should be installed"


@pytest.mark.requires_usb
def test_usb_audio_device_detected(host):
    """Test that USB audio device is detected."""
    result = host.run("aplay -l | grep -i usb")
    if result.rc != 0:
        pytest.skip("No USB audio device connected")


def test_intercom_control_script_exists(host):
    """Test that intercom control script exists."""
    control_script = host.file("/usr/local/bin/ndi-bridge-intercom-control")
    assert control_script.exists, "Intercom control script should exist"
    assert control_script.mode & 0o111, "Control script should be executable"


def test_intercom_config_script_exists(host):
    """Test that intercom config script exists."""
    config_script = host.file("/usr/local/bin/ndi-bridge-intercom-config")
    assert config_script.exists, "Intercom config script should exist"
    assert config_script.mode & 0o111, "Config script should be executable"


def test_xvfb_installed(host):
    """Test that Xvfb is installed for virtual display."""
    result = host.run("which Xvfb")
    assert result.rc == 0, "Xvfb should be installed"


def test_x11vnc_installed(host):
    """Test that x11vnc is installed for remote access."""
    result = host.run("which x11vnc")
    assert result.rc == 0, "x11vnc should be installed"


def test_intercom_pipewire_script_exists(host):
    """Test that PipeWire implementation script exists."""
    script = host.file("/usr/local/bin/ndi-bridge-intercom-pipewire")
    assert script.exists, "PipeWire implementation script should exist"
    assert script.mode & 0o111, "Script should be executable"


def test_intercom_monitor_script_exists(host):
    """Test that monitor script exists."""
    script = host.file("/usr/local/bin/ndi-bridge-intercom-monitor")
    assert script.exists, "Monitor script should exist"
    assert script.mode & 0o111, "Script should be executable"


# Note: For comprehensive intercom testing, see tests/component/intercom/ directory:
# - test_intercom_core.py: Core service and script tests
# - test_intercom_processes.py: Runtime process tests
# - test_intercom_audio.py: Audio functionality tests
# - test_intercom_config.py: Configuration persistence tests
# - test_intercom_web.py: Web interface tests
# - test_intercom_integration.py: Complete workflow tests
# - test_intercom_rename_comprehensive.py: Device rename tests (issue #53)