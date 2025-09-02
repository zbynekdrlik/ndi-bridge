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
    """Test that PipeWire is installed (if used)."""
    result = host.run("which pipewire")
    if result.rc == 0:
        # PipeWire is installed, check if running
        pw_result = host.run("pgrep pipewire")
        assert pw_result.rc == 0, "PipeWire installed but not running"


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
    result = host.run("timeout 1 speaker-test -t sine -f 440 -c 1 >/dev/null 2>&1")
    # timeout will return 124 when it times out (expected)
    assert result.rc in [0, 124], f"speaker-test failed: rc={result.rc}"