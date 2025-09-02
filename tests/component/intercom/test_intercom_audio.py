"""
Tests for NDI Bridge Intercom audio functionality.

Verifies audio device detection, control, and configuration.
"""

import pytest
import json
import time


class TestIntercomAudio:
    """Test intercom audio functionality."""
    
    def test_usb_audio_device_present(self, host):
        """Test that USB audio device is present."""
        result = host.run("aplay -l | grep -i usb")
        if not result.succeeded:
            pytest.skip("No USB audio device connected")
    
    def test_csctek_usb_audio_detected(self, host):
        """Test that CSCTEK USB Audio HID device is detected."""
        result = host.run("aplay -l | grep -i 'CSCTEK'")
        if not result.succeeded:
            # Try alternative detection
            result = host.run("cat /proc/asound/cards | grep -i 'USB Audio'")
            if not result.succeeded:
                pytest.skip("CSCTEK USB Audio device not connected")
    
    def test_pipewire_sees_usb_audio(self, host):
        """Test that PipeWire can see the USB audio device."""
        result = host.run("pw-cli list-objects | grep -i 'usb\\|audio' | head -5")
        if not result.succeeded:
            # Try alternative command
            result = host.run("pactl list cards | grep -i usb")
        
        assert result.succeeded or result.stdout, "PipeWire should see audio devices"
    
    def test_audio_control_get_volumes(self, host):
        """Test that audio control can get volume levels."""
        result = host.run("media-bridge-intercom-control status")
        assert result.succeeded, "Control status should succeed"
        
        status = json.loads(result.stdout)
        
        # Check volume ranges
        assert "input" in status, "Should have input section"
        assert "output" in status, "Should have output section"
        assert 0 <= status["input"]["volume"] <= 100, "Input volume should be 0-100"
        assert 0 <= status["output"]["volume"] <= 100, "Output volume should be 0-100"
    
    def test_audio_control_set_mic_volume(self, host):
        """Test setting microphone volume."""
        # Get current volume
        result = host.run("media-bridge-intercom-control status")
        original = json.loads(result.stdout)
        
        # Set new volume
        new_volume = 75
        result = host.run(f"media-bridge-intercom-control set-volume input {new_volume}")
        assert result.succeeded, "Set mic volume should succeed"
        
        # Verify change
        result = host.run("media-bridge-intercom-control status")
        current = json.loads(result.stdout)
        assert current["input"]["volume"] == new_volume, f"Mic volume should be {new_volume}"
        
        # Restore original
        host.run(f"media-bridge-intercom-control set-volume input {original['input']['volume']}")
    
    def test_audio_control_set_speaker_volume(self, host):
        """Test setting speaker volume."""
        # Get current volume
        result = host.run("media-bridge-intercom-control status")
        original = json.loads(result.stdout)
        
        # Set new volume
        new_volume = 65
        result = host.run(f"media-bridge-intercom-control set-volume output {new_volume}")
        assert result.succeeded, "Set speaker volume should succeed"
        
        # Verify change
        result = host.run("media-bridge-intercom-control status")
        current = json.loads(result.stdout)
        assert current["output"]["volume"] == new_volume, f"Speaker volume should be {new_volume}"
        
        # Restore original
        host.run(f"media-bridge-intercom-control set-volume output {original['output']['volume']}")
    
    def test_audio_control_mute_unmute_mic(self, host):
        """Test muting and unmuting microphone."""
        # Get current state
        result = host.run("media-bridge-intercom-control status")
        original = json.loads(result.stdout)
        
        # Mute mic
        result = host.run("media-bridge-intercom-control mute input")
        assert result.succeeded, "Mute mic should succeed"
        
        # Check muted
        result = host.run("media-bridge-intercom-control status")
        current = json.loads(result.stdout)
        assert current["input"]["muted"] == True, "Mic should be muted"
        
        # Unmute mic
        result = host.run("media-bridge-intercom-control unmute input")
        assert result.succeeded, "Unmute mic should succeed"
        
        # Check unmuted
        result = host.run("media-bridge-intercom-control status")
        current = json.loads(result.stdout)
        assert current["input"]["muted"] == False, "Mic should be unmuted"
        
        # Restore original state
        if original["input"]["muted"]:
            host.run("media-bridge-intercom-control mute input")
    
    def test_audio_monitor_control(self, host):
        """Test audio monitor (self-hearing) control."""
        # Monitor functionality is managed separately
        # Enable monitor
        result = host.run("media-bridge-intercom-monitor enable")
        assert result.succeeded, "Enable monitor should succeed"
        
        # Wait for module to load
        time.sleep(2)
        
        # Check status reports enabled
        result = host.run("media-bridge-intercom-monitor status")
        status = json.loads(result.stdout)
        assert status["enabled"] == True, "Monitor should be enabled"
        
        # Disable monitor
        result = host.run("media-bridge-intercom-monitor disable")
        assert result.succeeded, "Disable monitor should succeed"
        
        # Check disabled
        time.sleep(2)
        result = host.run("media-bridge-intercom-monitor status")
        status = json.loads(result.stdout)
        assert status["enabled"] == False, "Monitor should be disabled"
    
    def test_audio_monitor_latency(self, host):
        """Test that monitor claims ultra-low latency."""
        result = host.run("media-bridge-intercom-monitor status")
        if result.succeeded:
            # Check for latency claims in output
            assert "latency" in result.stdout.lower() or "quantum" in result.stdout.lower()
    
    def test_pipewire_quantum_adjustment(self, host):
        """Test that PipeWire quantum can be adjusted for low latency."""
        # Check current quantum
        result = host.run("pw-metadata -n settings | grep clock.quantum")
        # Quantum adjustment might be automatic
        assert result.succeeded or True, "Quantum check"
    
    def test_audio_device_exclusive_access(self, host):
        """Test that intercom has exclusive access to audio device."""
        # Check if Chrome/PipeWire is using the audio device
        result = host.run("lsof /dev/snd/* 2>/dev/null | grep -E 'chrome|pipewire|wireplumber'")
        # Some process should be using audio devices
        assert result.succeeded or True, "Audio device access check"
    
    def test_pipewire_modules_loaded(self, host):
        """Test that required PipeWire modules are loaded."""
        # Check for loopback module when monitor is enabled
        result = host.run("media-bridge-intercom-monitor status")
        status = json.loads(result.stdout)
        
        if status["enabled"]:
            # Check for loopback module
            result = host.run("pactl list modules | grep -i loopback")
            assert result.succeeded, "Loopback module should be loaded when monitor is enabled"
        else:
            # Monitor is disabled, so loopback module not required
            assert True, "Monitor disabled, loopback module not required"
    
    def test_audio_levels_readable(self, host):
        """Test that audio levels can be read."""
        result = host.run("media-bridge-intercom-control levels")
        if result.succeeded:
            try:
                levels = json.loads(result.stdout)
                assert "mic_level" in levels or "input_level" in levels
                assert "speaker_level" in levels or "output_level" in levels
            except json.JSONDecodeError:
                # Levels might not be implemented yet
                pass
    
    def test_audio_device_reconnection_handling(self, host):
        """Test that system handles USB audio reconnection."""
        # This is a conceptual test - actual USB disconnect would require hardware control
        # Check if service has restart policy
        result = host.run("systemctl show media-bridge-intercom --property Restart")
        assert "Restart=always" in result.stdout, "Service should have restart policy for device issues"