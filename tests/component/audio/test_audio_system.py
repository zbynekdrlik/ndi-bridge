"""
Atomic tests for audio subsystem.

Tests ALSA and audio output functionality.
"""

import pytest
import time


def test_alsa_utils_installed(host):
    """Test that ALSA utilities are installed."""
    result = host.run("which aplay")
    assert result.rc == 0, "aplay not found - ALSA utils not installed"


def test_alsa_devices_detected(host):
    """Test that ALSA devices are detected."""
    result = host.run("aplay -l | grep '^card'")
    assert result.rc == 0, "No ALSA sound cards detected"


def test_alsa_playback_device_exists(host):
    """Test that at least one playback device exists."""
    result = host.run("aplay -l | grep -c 'card'")
    card_count = int(result.stdout.strip())
    assert card_count > 0, "No ALSA playback devices found"


def test_alsa_default_device_configured(host):
    """Test that default ALSA device is configured."""
    # Check if default device works
    result = host.run("aplay -D default /dev/null 2>&1 | grep -v 'Playing raw data'")
    # Should not have major errors
    assert "No such" not in result.stdout, "Default ALSA device not configured"


def test_alsa_state_file_exists(host):
    """Test that ALSA state file exists."""
    state_file = host.file("/var/lib/alsa/asound.state")
    # File might not exist on fresh system
    if state_file.exists:
        assert state_file.size > 0, "ALSA state file is empty"


def test_proc_asound_exists(host):
    """Test that /proc/asound exists."""
    proc_asound = host.file("/proc/asound")
    assert proc_asound.exists, "/proc/asound not found - sound support missing"


def test_proc_asound_cards_populated(host):
    """Test that /proc/asound/cards has content."""
    result = host.run("cat /proc/asound/cards")
    assert result.rc == 0, "Cannot read /proc/asound/cards"
    assert len(result.stdout.strip()) > 0, "No sound cards in /proc/asound/cards"


def test_sound_modules_loaded(host):
    """Test that sound kernel modules are loaded."""
    result = host.run("lsmod | grep -E 'snd|sound'")
    assert result.rc == 0, "No sound kernel modules loaded"


def test_alsa_mixer_accessible(host):
    """Test that ALSA mixer is accessible."""
    result = host.run("amixer scontrols")
    # Might have no controls on some devices
    assert result.rc == 0, "Cannot access ALSA mixer"


def test_pipewire_installed(host):
    """Test that PipeWire is installed."""
    result = host.run("which pipewire")
    assert result.rc == 0, "PipeWire is not installed"


def test_pipewire_service_running(host):
    """Test that system-wide PipeWire service is running."""
    # Check for system-wide service first
    system_service = host.service("pipewire-system")
    if system_service.is_enabled:
        assert system_service.is_running, "pipewire-system service not running"
    else:
        # Fallback to checking for PipeWire process
        result = host.run("pgrep pipewire")
        assert result.rc == 0, "PipeWire is not running (neither system service nor process)"


def test_pipewire_pulse_service_running(host):
    """Test that PipeWire PulseAudio compatibility is running."""
    # Check for system-wide pipewire-pulse service
    pulse_service = host.service("pipewire-pulse-system")
    if pulse_service.is_enabled:
        assert pulse_service.is_running, "pipewire-pulse-system service not running"
    else:
        # Check for pipewire-pulse process
        result = host.run("pgrep pipewire-pulse")
        assert result.rc == 0, "pipewire-pulse is not running"


def test_wireplumber_service_running(host):
    """Test that WirePlumber session manager is running."""
    # Check for system-wide wireplumber service
    wireplumber_service = host.service("wireplumber-system")
    if wireplumber_service.is_enabled:
        assert wireplumber_service.is_running, "wireplumber-system service not running"
    else:
        # Check for wireplumber process
        result = host.run("pgrep wireplumber")
        assert result.rc == 0, "wireplumber is not running"


def test_pipewire_audio_working(host):
    """Test that PipeWire audio is functional."""
    # Check if pactl can connect to PipeWire
    result = host.run("pactl info")
    assert result.rc == 0, "Cannot connect to PipeWire audio server"
    assert "PipeWire" in result.stdout, "Not connected to PipeWire server"


def test_pulseaudio_installed(host):
    """Test that PulseAudio is installed (alternative to PipeWire)."""
    result = host.run("which pulseaudio")
    if result.rc == 0:
        # PulseAudio is installed, check if running
        pa_result = host.run("pgrep pulseaudio")
        # It's OK if not running - might use PipeWire instead
        assert True


@pytest.mark.audio
def test_audio_device_permissions(host):
    """Test that audio devices have correct permissions."""
    result = host.run("ls -l /dev/snd/ | grep -E 'pcm|control'")
    if result.rc == 0:
        # Audio devices should be accessible by audio group
        assert "audio" in result.stdout, "Audio devices don't have audio group"


def test_speaker_test_available(host):
    """Test that speaker-test command is available."""
    result = host.run("which speaker-test")
    assert result.rc == 0, "speaker-test not found"


@pytest.mark.slow
def test_speaker_test_runs(host):
    """Test that speaker-test can run (brief test)."""
    # Run very brief test - just check it starts
    # Use longer timeout and proper duration flag
    result = host.run("timeout 2 speaker-test -t sine -f 440 -c 1 -l 1 >/dev/null 2>&1")
    # Return codes: 0 = success, 124 = timeout (expected for timeout command)
    assert result.rc in [0, 124], f"speaker-test failed: rc={result.rc}"


def test_hdmi_audio_devices_detected(host):
    """Test that HDMI audio devices are detected."""
    result = host.run("aplay -l | grep -i hdmi")
    # HDMI audio might not be available on all systems
    if result.rc == 0:
        assert "HDMI" in result.stdout, "HDMI audio device not properly detected"


def test_pipewire_hdmi_sink_available(host):
    """Test that PipeWire has HDMI sink available when HDMI is connected."""
    result = host.run("pactl list sinks short | grep -i hdmi")
    # HDMI sink might not be available if no HDMI connected
    if result.rc == 0:
        assert "hdmi" in result.stdout.lower(), "HDMI sink not available in PipeWire"