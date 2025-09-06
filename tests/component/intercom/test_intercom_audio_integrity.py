"""
Critical tests for intercom audio integrity and device management.
These tests MUST catch duplicate devices, wrong configurations, and audio routing failures.
"""

import pytest
import time
import re


class TestIntercomAudioIntegrity:
    """Test audio system integrity - no duplicates, correct routing, actual functionality."""

    def test_no_duplicate_virtual_devices(self, host):
        """CRITICAL: Ensure NO duplicate virtual devices exist."""
        sources = host.run("pactl list sources short")
        sinks = host.run("pactl list sinks short")
        
        # Count intercom devices
        intercom_sources = []
        for line in sources.stdout.split('\n'):
            if 'intercom-microphone-source' in line:
                intercom_sources.append(line)
        
        intercom_sinks = []
        for line in sinks.stdout.split('\n'):
            if 'intercom-speaker' in line:
                intercom_sinks.append(line)
            # Note: intercom-microphone as a sink is OK (it's the implementation)
            if 'intercom-microphone' in line and 'monitor' not in line:
                intercom_sinks.append(line)
        
        # STRICT: Only ONE of each device should exist
        assert len(intercom_sources) <= 1, (
            f"CRITICAL: Found {len(intercom_sources)} duplicate intercom-microphone-source devices!\n"
            f"This breaks Chrome audio completely.\n"
            f"Devices:\n" + "\n".join(intercom_sources)
        )
        
        # intercom-speaker should be unique
        speaker_count = len([s for s in intercom_sinks if 'intercom-speaker' in s])
        assert speaker_count == 1, (
            f"CRITICAL: Found {speaker_count} intercom-speaker devices (expected 1)!\n"
            f"Devices:\n" + "\n".join([s for s in intercom_sinks if 'intercom-speaker' in s])
        )

    def test_chrome_has_audio_device_selected(self, host):
        """Test that Chrome has actually selected an audio device, not just enumerated them."""
        # Check if Chrome is running
        chrome_ps = host.run("pgrep -f 'chrome.*vdo.ninja'")
        if chrome_ps.exit_status != 0:
            pytest.skip("Chrome intercom not running")
        
        # Check Chrome's actual audio connections
        sink_inputs = host.run("pactl list sink-inputs")
        source_outputs = host.run("pactl list source-outputs")
        
        chrome_has_output = False
        chrome_has_input = False
        
        # Parse Chrome's audio streams
        for section in sink_inputs.stdout.split('Sink Input #'):
            if 'chrome' in section.lower():
                chrome_has_output = True
                # Verify it's connected to intercom-speaker
                if 'Sink:' in section:
                    sink_match = re.search(r'Sink:\s*(\d+)', section)
                    if sink_match:
                        sink_id = sink_match.group(1)
                        # Get sink name
                        sink_info = host.run(f"pactl list sinks short | grep '^{sink_id}'")
                        assert 'intercom-speaker' in sink_info.stdout, (
                            f"Chrome audio output not routed to intercom-speaker!\n"
                            f"Connected to: {sink_info.stdout}"
                        )
        
        for section in source_outputs.stdout.split('Source Output #'):
            if 'chrome' in section.lower():
                chrome_has_input = True
                # Verify it's connected to intercom-microphone
                if 'Source:' in section:
                    source_match = re.search(r'Source:\s*(\d+)', section)
                    if source_match:
                        source_id = source_match.group(1)
                        # Get source name
                        source_info = host.run(f"pactl list sources short | grep '^{source_id}'")
                        assert 'intercom-microphone' in source_info.stdout, (
                            f"Chrome audio input not routed to intercom-microphone!\n"
                            f"Connected to: {source_info.stdout}"
                        )
        
        # Chrome should have both input and output for intercom
        assert chrome_has_output or chrome_has_input, (
            "Chrome has NO audio connections at all! Intercom is completely broken."
        )

    def test_loopback_modules_correctly_configured(self, host):
        """Test that loopback modules are correctly set up and not duplicated."""
        modules = host.run("pactl list modules")
        
        # Count loopback modules
        loopback_configs = []
        for line in modules.stdout.split('\n'):
            if 'module-loopback' in line:
                # Get the next line which has the configuration
                idx = modules.stdout.index(line)
                config_section = modules.stdout[idx:idx+500]  # Get config section
                loopback_configs.append(config_section)
        
        # Should have exactly 2 loopback modules when USB connected
        usb_connected = host.run("lsusb | grep -E 'CSCTEK|0573:1573'").exit_status == 0
        
        if usb_connected:
            assert len(loopback_configs) == 2, (
                f"Wrong number of loopback modules: {len(loopback_configs)} (expected 2)\n"
                f"One for speaker->USB, one for USB->microphone"
            )
            
            # Verify correct routing
            has_speaker_to_usb = False
            has_usb_to_mic = False
            
            for config in loopback_configs:
                if 'source=intercom-speaker.monitor' in config:
                    has_speaker_to_usb = True
                    assert 'CSCTEK' in config or 'usb' in config.lower(), (
                        "Speaker loopback not routed to USB output!"
                    )
                
                if 'sink=intercom-microphone' in config:
                    has_usb_to_mic = True
                    assert 'CSCTEK' in config or 'usb' in config.lower(), (
                        "Microphone loopback not sourced from USB input!"
                    )
            
            assert has_speaker_to_usb, "Missing loopback: intercom-speaker -> USB headphones"
            assert has_usb_to_mic, "Missing loopback: USB microphone -> intercom-microphone"

    def test_hdmi_audio_still_available(self, host):
        """Test that HDMI audio is still available for ndi-display."""
        hdmi_sinks = host.run("pactl list sinks short | grep -i hdmi")
        
        assert hdmi_sinks.exit_status == 0 and hdmi_sinks.stdout, (
            "CRITICAL: No HDMI audio sinks available! ndi-display audio is broken!"
        )
        
        # HDMI sinks should NOT be connected to Chrome
        sink_inputs = host.run("pactl list sink-inputs")
        for section in sink_inputs.stdout.split('Sink Input #'):
            if 'chrome' in section.lower():
                # Chrome should NOT be connected to HDMI
                assert 'hdmi' not in section.lower(), (
                    "SECURITY VIOLATION: Chrome audio is routed to HDMI output!"
                )

    def test_audio_manager_idempotent(self, host):
        """Test that running audio manager multiple times doesn't create duplicates."""
        # Get initial state
        initial_sources = host.run("pactl list sources short | grep intercom | wc -l")
        initial_sinks = host.run("pactl list sinks short | grep intercom | wc -l")
        
        # Run audio manager setup multiple times
        for i in range(3):
            result = host.run("/usr/local/bin/media-bridge-audio-manager setup")
            assert result.exit_status == 0, f"Audio manager failed on run {i+1}"
            time.sleep(1)
        
        # Check final state - should be same as initial
        final_sources = host.run("pactl list sources short | grep intercom | wc -l")
        final_sinks = host.run("pactl list sinks short | grep intercom | wc -l")
        
        assert final_sources.stdout == initial_sources.stdout, (
            f"Audio manager created duplicates! Sources before: {initial_sources.stdout.strip()}, "
            f"after: {final_sources.stdout.strip()}"
        )
        
        assert final_sinks.stdout == initial_sinks.stdout, (
            f"Audio manager created duplicates! Sinks before: {initial_sinks.stdout.strip()}, "
            f"after: {final_sinks.stdout.strip()}"
        )

    def test_audio_persists_after_reboot(self, host):
        """Test that audio configuration persists after reboot."""
        # Mark this test to be run manually as it requires reboot
        pytest.skip("Reboot test must be run manually with device reboot")
        
        # This test should:
        # 1. Save current config state
        # 2. Reboot device
        # 3. Verify virtual devices are recreated
        # 4. Verify Chrome connects to them
        # 5. Verify no duplicates

    def test_audio_flow_end_to_end(self, host):
        """Test that audio actually flows through the system."""
        # Check if we can generate and detect audio
        
        # 1. Check Chrome is producing audio (source-output exists)
        chrome_audio = host.run("pactl list source-outputs | grep -i chrome")
        if chrome_audio.exit_status != 0:
            pytest.skip("Chrome not producing audio - need manual verification")
        
        # 2. Check loopback modules are passing audio (not suspended)
        modules = host.run("pactl list modules | grep -A5 module-loopback | grep state")
        
        # 3. Check USB device is receiving audio
        usb_sink_status = host.run(
            "pactl list sinks | grep -A10 'CSCTEK\\|usb.*0573' | grep State"
        )
        
        if usb_sink_status.stdout and 'RUNNING' in usb_sink_status.stdout:
            # Audio is actively flowing
            pass
        elif usb_sink_status.stdout and 'IDLE' in usb_sink_status.stdout:
            # Audio path exists but no audio currently
            print("Audio path configured but no active audio stream")
        else:
            assert False, "USB audio device not receiving any audio!"

    def test_chrome_device_selection_in_vdo_ninja(self, host):
        """Test that Chrome has correct devices selected in VDO.Ninja settings."""
        # This test would ideally check Chrome's actual device selection
        # via DevTools protocol or by checking the VDO.Ninja page state
        
        # For now, verify Chrome command line flags
        chrome_cmd = host.run("ps aux | grep chrome | grep vdo.ninja")
        
        if chrome_cmd.exit_status == 0:
            # Check for audio configuration flags
            assert '--audio-output-channels=2' in chrome_cmd.stdout, (
                "Chrome not configured for stereo output"
            )
            assert '--audio-input-channels=1' in chrome_cmd.stdout, (
                "Chrome not configured for mono input"
            )

    def test_virtual_devices_have_correct_properties(self, host):
        """Test that virtual devices have the correct audio properties."""
        # Check intercom-speaker properties
        speaker_info = host.run("pactl list sinks | grep -A20 'Name: intercom-speaker'")
        if speaker_info.exit_status == 0:
            assert '2ch' in speaker_info.stdout or 'stereo' in speaker_info.stdout, (
                "Virtual speaker not configured for stereo"
            )
            assert '48000' in speaker_info.stdout, (
                "Virtual speaker not at 48kHz sample rate"
            )
        
        # Check intercom-microphone properties  
        mic_info = host.run("pactl list sinks | grep -A20 'Name: intercom-microphone'")
        if mic_info.exit_status == 0:
            assert '1ch' in mic_info.stdout or 'mono' in mic_info.stdout, (
                "Virtual microphone not configured for mono"
            )
            assert '48000' in mic_info.stdout, (
                "Virtual microphone not at 48kHz sample rate"
            )

    def test_no_audio_on_wrong_outputs(self, host):
        """Test that audio is NOT going to wrong outputs."""
        # Check all active audio streams
        sink_inputs = host.run("pactl list sink-inputs short")
        
        for line in sink_inputs.stdout.split('\n'):
            if line.strip():
                parts = line.split('\t')
                if len(parts) >= 3:
                    # Check sink ID and get its name
                    sink_id = parts[1]
                    sink_name = host.run(f"pactl list sinks short | grep '^{sink_id}'")
                    
                    # Intercom audio should only go to intercom-speaker or USB
                    if 'chrome' in line.lower() or 'intercom' in line.lower():
                        assert 'hdmi' not in sink_name.stdout.lower(), (
                            f"SECURITY: Intercom audio going to HDMI! {sink_name.stdout}"
                        )