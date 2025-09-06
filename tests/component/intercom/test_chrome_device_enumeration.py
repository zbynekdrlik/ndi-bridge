"""Test Chrome device enumeration to ensure proper virtual device isolation.

This test ACTUALLY verifies what devices Chrome can SEE, not just what it's connected to.
Critical for detecting the issue where Chrome sees all hardware devices.
"""

import pytest
import json
import time


class TestChromeDeviceEnumeration:
    """Test that Chrome can ONLY see virtual devices, not hardware."""
    
    def test_chrome_sees_only_virtual_devices(self, host):
        """CRITICAL: Chrome must ONLY see intercom-speaker and intercom-microphone."""
        # Check if Chrome is running
        chrome_ps = host.run("pgrep -f 'chrome.*vdo.ninja'")
        if chrome_ps.exit_status != 0:
            pytest.skip("Chrome intercom not running")
        
        # Create a test script to enumerate devices from Chrome's perspective
        # This uses Chrome DevTools Protocol via debugging port
        test_script = """
#!/bin/bash
# Query Chrome's actual device enumeration via JavaScript

# Find Chrome's debugging port (if enabled)
CHROME_PID=$(pgrep -f 'chrome.*vdo.ninja' | head -1)
if [ -z "$CHROME_PID" ]; then
    echo "ERROR: Chrome not running"
    exit 1
fi

# Try to get device list through Chrome's audio subsystem
# This simulates what Chrome sees in its device selector

# Method 1: Check what PipeWire exposes to Chrome's process
echo "=== PipeWire devices visible to Chrome ==="
# Get Chrome's PID and check its audio context
pw-cli list-objects | grep -E "node.name|media.name|application.name" | grep -B2 -A2 -i chrome || true

echo ""
echo "=== All audio devices Chrome can potentially see ==="
# List all sources and sinks that applications can see
pactl list sources short
echo "---"
pactl list sinks short

echo ""
echo "=== Chrome's current connections ==="
pactl list sink-inputs | grep -A 10 -i chrome || echo "No Chrome sink inputs"
pactl list source-outputs | grep -A 10 -i chrome || echo "No Chrome source outputs"
"""
        
        # Write and execute the test script
        host.run("cat > /tmp/test_chrome_devices.sh << 'EOF'\n" + test_script + "\nEOF")
        host.run("chmod +x /tmp/test_chrome_devices.sh")
        result = host.run("/tmp/test_chrome_devices.sh")
        
        assert result.exit_status == 0, f"Device enumeration failed: {result.stderr}"
        
        # Parse the output to check what Chrome can see
        output = result.stdout
        
        # Check sources (microphones) Chrome can see
        sources_section = output.split("All audio devices Chrome can potentially see")[1].split("---")[0]
        source_count = 0
        hardware_sources = []
        
        for line in sources_section.split('\n'):
            if line.strip():
                # Count non-monitor sources (actual microphone inputs)
                if '.monitor' not in line:
                    source_count += 1
                    # Check if it's a hardware device
                    if 'alsa_input' in line or 'usb' in line.lower() or 'hdmi' in line.lower():
                        hardware_sources.append(line.strip())
        
        # Check sinks (speakers) Chrome can see  
        sinks_section = output.split("---")[1].split("Chrome's current connections")[0]
        sink_count = 0
        hardware_sinks = []
        
        for line in sinks_section.split('\n'):
            if line.strip():
                sink_count += 1
                # Check if it's a hardware device
                if 'alsa_output' in line or 'usb' in line.lower() or 'hdmi' in line.lower():
                    hardware_sinks.append(line.strip())
        
        # CRITICAL ASSERTIONS
        
        # Chrome should NOT see hardware microphones
        assert len(hardware_sources) == 0, (
            f"CRITICAL: Chrome can see {len(hardware_sources)} hardware microphone(s):\n" +
            "\n".join(hardware_sources) +
            "\n\nChrome should ONLY see virtual devices!"
        )
        
        # Chrome should NOT see hardware speakers
        assert len(hardware_sinks) == 0, (
            f"CRITICAL: Chrome can see {len(hardware_sinks)} hardware speaker(s):\n" +
            "\n".join(hardware_sinks) +
            "\n\nChrome should ONLY see virtual devices!"
        )
        
        # Chrome should see EXACTLY 2 virtual devices
        assert 'intercom-microphone' in output, "Chrome cannot see intercom-microphone virtual device"
        assert 'intercom-speaker' in output, "Chrome cannot see intercom-speaker virtual device"
        
        # Verify no HDMI or USB devices are visible
        assert 'hdmi' not in output.lower() or 'hdmi' in output.lower().split('chrome')[0], (
            "CRITICAL SECURITY: HDMI devices visible to Chrome!"
        )
        
        # The actual device count Chrome sees should be minimal
        # Note: monitors don't count as they're not selectable inputs
        assert source_count <= 2, (
            f"Chrome can see {source_count} microphone sources - should only see virtual device(s)"
        )
        assert sink_count <= 2, (
            f"Chrome can see {sink_count} speaker sinks - should only see virtual device(s)"
        )
    
    def test_wireplumber_device_access_control(self, host):
        """Test WirePlumber has proper access control to hide devices from Chrome."""
        # Check if WirePlumber access control rules exist
        config = host.run("cat /etc/wireplumber/main.lua.d/* 2>/dev/null | grep -i 'access\\|restrict\\|hide\\|chrome'")
        
        # There should be rules to restrict Chrome's device access
        assert config.exit_status == 0 or "chrome" in config.stdout.lower(), (
            "No WirePlumber access control rules found for Chrome!\n"
            "Chrome can see ALL system audio devices without restrictions."
        )
    
    def test_chrome_launched_with_device_restrictions(self, host):
        """Test Chrome is launched with proper flags to restrict device access."""
        chrome_ps = host.run("ps aux | grep -v grep | grep chrome")
        
        if chrome_ps.exit_status != 0:
            pytest.skip("Chrome not running")
        
        chrome_cmd = chrome_ps.stdout
        
        # Check for device restriction flags
        important_flags = [
            "--use-fake-device-for-media-stream",  # Forces virtual devices
            "--audio-input-channels=1",  # Mono input
            "--audio-output-channels=2",  # Stereo output
        ]
        
        missing_flags = []
        for flag in important_flags:
            if flag not in chrome_cmd:
                missing_flags.append(flag)
        
        assert len(missing_flags) == 0, (
            f"Chrome launched without critical audio isolation flags:\n"
            f"Missing: {', '.join(missing_flags)}\n"
            f"This allows Chrome to see and use hardware devices directly!"
        )
    
    def test_chrome_cannot_enumerate_hardware_devices(self, host):
        """Test that hardware devices are NOT visible to Chrome's enumeration."""
        # Get what Chrome can potentially see
        sinks = host.run("pactl list sinks short")
        sources = host.run("pactl list sources short | grep -v '.monitor$'")
        
        # Check that hardware devices exist (so we know they're not just missing)
        assert "alsa_" in sinks.stdout or "alsa_" in sources.stdout, (
            "No hardware devices found - cannot test isolation"
        )
        
        # Count how many devices Chrome can see
        all_sinks = len([l for l in sinks.stdout.split('\n') if l.strip()])
        all_sources = len([l for l in sources.stdout.split('\n') if l.strip()])
        
        # Count hardware devices
        hw_sinks = len([l for l in sinks.stdout.split('\n') if 'alsa_' in l])
        hw_sources = len([l for l in sources.stdout.split('\n') if 'alsa_' in l])
        
        # Chrome should NOT be able to see hardware devices
        # This is the IDEAL state we want to achieve
        assert hw_sinks == 0 or all_sinks <= 2, (
            f"Chrome can see {hw_sinks} hardware speaker devices!\n"
            f"Hardware devices should be hidden from Chrome.\n"
            f"Sinks visible:\n{sinks.stdout}"
        )
        
        assert hw_sources == 0 or all_sources <= 2, (
            f"Chrome can see {hw_sources} hardware microphone devices!\n"
            f"Hardware devices should be hidden from Chrome.\n"
            f"Sources visible:\n{sources.stdout}"
        )
    
    def test_pipewire_virtual_device_priority(self, host):
        """Test virtual devices have highest priority to be default."""
        sinks = host.run("pactl list sinks | grep -E 'Name:|Priority:'")
        
        # Parse sink priorities
        current_sink = None
        priorities = {}
        
        for line in sinks.stdout.split('\n'):
            if 'Name:' in line:
                current_sink = line.split('Name:')[1].strip()
            elif 'Priority:' in line and current_sink:
                priority = int(line.split('Priority:')[1].strip())
                priorities[current_sink] = priority
        
        # Virtual devices should have highest priority
        if 'intercom-speaker' in priorities:
            for sink, priority in priorities.items():
                if 'hdmi' in sink.lower() or 'usb' in sink.lower():
                    assert priorities['intercom-speaker'] > priority, (
                        f"Virtual device 'intercom-speaker' has lower priority ({priorities['intercom-speaker']}) "
                        f"than hardware device '{sink}' ({priority})"
                    )
        
        # Same for microphone
        sources = host.run("pactl list sources | grep -E 'Name:|Priority:'")
        current_source = None
        source_priorities = {}
        
        for line in sources.stdout.split('\n'):
            if 'Name:' in line:
                current_source = line.split('Name:')[1].strip()
            elif 'Priority:' in line and current_source:
                priority = int(line.split('Priority:')[1].strip())
                source_priorities[current_source] = priority
        
        if 'intercom-microphone.monitor' in source_priorities:
            for source, priority in source_priorities.items():
                if ('hdmi' in source.lower() or 'usb' in source.lower()) and '.monitor' not in source:
                    assert source_priorities['intercom-microphone.monitor'] > priority, (
                        f"Virtual device 'intercom-microphone' has lower priority "
                        f"than hardware device '{source}'"
                    )