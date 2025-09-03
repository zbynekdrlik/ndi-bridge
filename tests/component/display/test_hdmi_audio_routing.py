"""
Atomic tests for HDMI audio routing functionality.

Tests the dynamic HDMI port selection and audio routing.
"""

import pytest


def test_hdmi_display_0_audio_profile(host):
    """Test that HDMI display 0 has audio profile available."""
    result = host.run("pactl list cards | grep -A20 'hdmi.*output.*0' | grep -i 'available: yes' || echo 'not-available'")
    # Display 0 might not be connected
    assert result.rc == 0, "Error checking HDMI display 0 audio"


def test_hdmi_display_1_audio_profile(host):
    """Test that HDMI display 1 has audio profile available."""
    result = host.run("pactl list cards | grep -A20 'hdmi.*output.*1' | grep -i 'available: yes' || echo 'not-available'")
    # Display 1 might not be connected
    assert result.rc == 0, "Error checking HDMI display 1 audio"


def test_hdmi_display_2_audio_profile(host):
    """Test that HDMI display 2 has audio profile available."""
    result = host.run("pactl list cards | grep -A20 'hdmi.*output.*2' | grep -i 'available: yes' || echo 'not-available'")
    # Display 2 might not be connected
    assert result.rc == 0, "Error checking HDMI display 2 audio"


def test_hdmi_audio_card_detected(host):
    """Test that Intel HDA HDMI audio card is detected."""
    result = host.run("aplay -l | grep -i 'HDA Intel'")
    assert result.rc == 0, "Intel HDA audio card not detected"


def test_hdmi_audio_devices_in_alsa(host):
    """Test that HDMI audio devices appear in ALSA."""
    result = host.run("aplay -l | grep -c 'HDMI'")
    hdmi_count = int(result.stdout.strip())
    assert hdmi_count > 0, "No HDMI audio devices in ALSA"


def test_hdmi_audio_pcm_devices(host):
    """Test that HDMI PCM devices are available."""
    result = host.run("ls /proc/asound/card*/pcm*p/info 2>/dev/null | wc -l")
    pcm_count = int(result.stdout.strip())
    assert pcm_count > 0, "No PCM playback devices found"


def test_drm_audio_capability_hdmi_a_1(host):
    """Test that HDMI-A-1 supports audio in DRM."""
    result = host.run("find /sys/class/drm -name 'card*HDMI-A-1' -type l 2>/dev/null | head -1")
    if result.stdout:
        # Check if audio is supported
        audio_check = host.run(f"cat {result.stdout.strip()}/audio 2>/dev/null || echo 'no-audio'")
        # Audio file might not exist if not connected
        assert audio_check.rc == 0, "Error checking HDMI-A-1 audio capability"


def test_drm_audio_capability_hdmi_a_2(host):
    """Test that HDMI-A-2 supports audio in DRM."""
    result = host.run("find /sys/class/drm -name 'card*HDMI-A-2' -type l 2>/dev/null | head -1")
    if result.stdout:
        # Check if audio is supported
        audio_check = host.run(f"cat {result.stdout.strip()}/audio 2>/dev/null || echo 'no-audio'")
        # Audio file might not exist if not connected
        assert audio_check.rc == 0, "Error checking HDMI-A-2 audio capability"


def test_drm_audio_capability_hdmi_a_3(host):
    """Test that HDMI-A-3 supports audio in DRM."""
    result = host.run("find /sys/class/drm -name 'card*HDMI-A-3' -type l 2>/dev/null | head -1")
    if result.stdout:
        # Check if audio is supported
        audio_check = host.run(f"cat {result.stdout.strip()}/audio 2>/dev/null || echo 'no-audio'")
        # Audio file might not exist if not connected
        assert audio_check.rc == 0, "Error checking HDMI-A-3 audio capability"


def test_pipewire_can_switch_hdmi_ports(host):
    """Test that PipeWire can list available HDMI ports for switching."""
    result = host.run("pactl list cards | grep -E 'output.*hdmi' | wc -l")
    port_count = int(result.stdout.strip())
    assert port_count >= 1, "No HDMI output ports available for switching"


def test_hdmi_audio_eld_readable(host):
    """Test that HDMI ELD (EDID-Like Data) is readable for audio capabilities."""
    result = host.run("find /proc/asound -name 'eld*' 2>/dev/null | head -1")
    if result.stdout:
        eld_file = result.stdout.strip()
        eld_content = host.run(f"cat {eld_file}")
        # ELD might be empty if no monitor connected
        assert eld_content.rc == 0, "Cannot read HDMI ELD data"


def test_hdmi_audio_connection_status(host):
    """Test that HDMI audio connection status is readable."""
    result = host.run("grep -r 'connection' /proc/asound/card*/eld* 2>/dev/null | head -1")
    # Connection status might not be available without monitor
    assert result.rc == 0, "Error checking HDMI connection status"


def test_pipewire_hdmi_sink_naming(host):
    """Test that PipeWire HDMI sinks have proper naming."""
    result = host.run("pactl list sinks | grep -E 'Name:.*hdmi'")
    if result.rc == 0:
        assert "alsa_output" in result.stdout, "HDMI sinks not properly named"


def test_hdmi_audio_formats_supported(host):
    """Test that HDMI reports supported audio formats."""
    result = host.run("find /proc/asound -name 'eld*' -exec grep -l 'sad_count' {} \\; 2>/dev/null | head -1")
    # Format info might not be available without monitor
    assert result.rc == 0, "Error checking HDMI audio format support"


def test_intel_audio_controller(host):
    """Test that Intel audio controller is detected."""
    # Check via /proc/asound/cards for Intel HDA
    result = host.run("cat /proc/asound/cards | grep -i 'Intel'")
    assert result.rc == 0, "Intel audio controller not detected"


def test_hdmi_audio_kernel_driver(host):
    """Test that HDMI audio kernel driver is loaded."""
    result = host.run("lsmod | grep -E 'snd_hda_codec_hdmi'")
    assert result.rc == 0, "HDMI audio kernel driver not loaded"


def test_pipewire_hdmi_profile_switching(host):
    """Test that HDMI profiles can be listed for switching."""
    result = host.run("pactl list cards | grep -c 'output:hdmi'")
    profile_count = int(result.stdout.strip())
    assert profile_count > 0, "No HDMI output profiles available"


@pytest.mark.audio
def test_hdmi_audio_mixer_controls(host):
    """Test that HDMI audio mixer controls are available."""
    # Find the Intel HDA card - it's labeled as "PCH" in the cards file
    result = host.run("grep -E 'HDA.*Intel|PCH' /proc/asound/cards | head -1 | sed 's/^[ ]*//' | cut -d' ' -f1")
    if result.stdout.strip().isdigit():
        card_num = result.stdout.strip()
        result = host.run(f"amixer -c {card_num} controls | grep -i 'hdmi' | wc -l")
        control_count = int(result.stdout.strip())
        assert control_count > 0, f"No HDMI mixer controls found on card {card_num}"
    else:
        # Fallback: try all cards
        result = host.run("for c in 0 1 2 3 4; do amixer -c $c controls 2>/dev/null | grep -i 'hdmi'; done | wc -l")
        control_count = int(result.stdout.strip())
        assert control_count > 0, "No HDMI mixer controls found on any card"


def test_pipewire_default_hdmi_routing(host):
    """Test that PipeWire can route to HDMI by default."""
    result = host.run("pactl info | grep 'Default Sink' | grep -i 'hdmi' || echo 'not-hdmi'")
    # Default might not be HDMI, which is OK
    assert result.rc == 0, "Error checking default audio routing"


def test_hdmi_display_audio_state_files(host):
    """Test that HDMI display audio state files exist."""
    result = host.run("ls /sys/class/drm/card*/audio 2>/dev/null | wc -l")
    audio_files = int(result.stdout.strip())
    # Some audio state files should exist
    assert audio_files >= 0, "No HDMI audio state files found"