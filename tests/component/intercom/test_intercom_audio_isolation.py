"""
Tests for strict PipeWire device isolation and permission-based filtering.
Chrome must ONLY see virtual intercom devices, nothing else.
ndi-display must ONLY see HDMI outputs, nothing else.
"""

import pytest
import json
import time


class TestPipeWireDeviceIsolation:
    """Test that PipeWire properly isolates devices per application."""
    
    def test_chrome_only_enumerates_intercom_devices(self, host):
        """Chrome must ONLY see intercom-speaker and intercom-microphone in device lists."""
        # Get Chrome's PID
        chrome_pid = host.run("pgrep -f 'chrome.*vdo.ninja' | head -1")
        if chrome_pid.exit_status != 0:
            pytest.skip("Chrome not running")
        
        pid = chrome_pid.stdout.strip()
        
        # Use pw-cli to check what devices Chrome can see
        # Chrome should ONLY see virtual devices
        chrome_objects = host.run(f"pw-cli dump | grep -A20 'client.id.*{pid}'")
        
        # Get all sinks Chrome can enumerate
        chrome_sinks = host.run(f"""
            pw-cli enum-params {pid} Route | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep -E 'sink|output' | sort -u
        """)
        
        if chrome_sinks.exit_status == 0 and chrome_sinks.stdout.strip():
            allowed_sinks = ['intercom-speaker']
            for sink in chrome_sinks.stdout.strip().split('\n'):
                assert any(allowed in sink for allowed in allowed_sinks), (
                    f"Chrome can see unauthorized sink: {sink}\n"
                    f"Only allowed: {allowed_sinks}"
                )
        
        # Get all sources Chrome can enumerate
        chrome_sources = host.run(f"""
            pw-cli enum-params {pid} Route | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | grep -E 'source|input' | sort -u
        """)
        
        if chrome_sources.exit_status == 0 and chrome_sources.stdout.strip():
            allowed_sources = ['intercom-microphone']
            for source in chrome_sources.stdout.strip().split('\n'):
                if 'monitor' not in source:  # Ignore monitor sources
                    assert any(allowed in source for allowed in allowed_sources), (
                        f"Chrome can see unauthorized source: {source}\n"
                        f"Only allowed: {allowed_sources}"
                    )
    
    def test_chrome_cannot_see_hardware_devices(self, host):
        """Chrome must NOT be able to enumerate any hardware devices."""
        # Get Chrome's client ID in PipeWire
        chrome_client = host.run("""
            pw-cli ls Node | grep -B5 'application.name = "Chrome"' | grep 'id:' | head -1 | awk '{print $2}'
        """)
        
        if chrome_client.exit_status != 0:
            pytest.skip("Chrome not connected to PipeWire")
        
        client_id = chrome_client.stdout.strip()
        
        # Check Chrome's permissions - should NOT have access to hardware devices
        forbidden_patterns = [
            'hdmi', 'HDMI',
            'usb', 'USB',
            'CSCTEK',
            'alsa_output.pci',
            'alsa_input.usb'
        ]
        
        # Get devices Chrome can see
        chrome_devices = host.run(f"pw-cli ls Node | grep -A3 'client.id = \"{client_id}\"'")
        
        for pattern in forbidden_patterns:
            assert pattern not in chrome_devices.stdout, (
                f"SECURITY VIOLATION: Chrome can see hardware device with pattern '{pattern}'\n"
                f"Chrome should ONLY see virtual intercom devices!"
            )
    
    def test_ndi_display_only_sees_hdmi(self, host):
        """ndi-display must ONLY see HDMI outputs, not intercom or USB devices."""
        # Check if ndi-display is running
        ndi_pid = host.run("pgrep -f '/opt/media-bridge/ndi-display' | head -1")
        if ndi_pid.exit_status != 0:
            pytest.skip("ndi-display not running")
        
        pid = ndi_pid.stdout.strip()
        
        # Get ndi-display's accessible devices
        ndi_devices = host.run(f"""
            pw-cli dump | grep -B10 -A10 'application.name = "ndi-display"' | 
            grep -E 'node.name|device.name' | cut -d'"' -f4
        """)
        
        if ndi_devices.exit_status == 0 and ndi_devices.stdout.strip():
            forbidden_patterns = [
                'intercom',
                'CSCTEK',
                'USB Audio'
            ]
            
            for pattern in forbidden_patterns:
                assert pattern not in ndi_devices.stdout, (
                    f"ndi-display can see forbidden device: {pattern}\n"
                    f"ndi-display should ONLY see HDMI outputs!"
                )
    
    def test_wireplumber_access_rules_loaded(self, host):
        """Verify WirePlumber has loaded strict isolation access rules."""
        # Check if access control script is loaded
        wp_config = host.run("wpctl status | grep -i 'access'")
        
        # Check for our custom isolation rules
        isolation_rules = host.run("ls /etc/wireplumber/main.lua.d/*isolation* 2>/dev/null")
        assert isolation_rules.exit_status == 0, (
            "WirePlumber isolation rules not found!\n"
            "Expected: /etc/wireplumber/main.lua.d/*isolation*"
        )
        
        # Verify rules are active
        wp_scripts = host.run("wpctl status | grep -i script")
        assert "access" in wp_scripts.stdout.lower() or "permission" in wp_scripts.stdout.lower(), (
            "WirePlumber access control not active!"
        )
    
    def test_permission_manager_service_running(self, host):
        """Verify permission manager service is active and managing access."""
        service_status = host.run("systemctl is-active media-bridge-permission-manager")
        assert service_status.stdout.strip() == "active", (
            "Permission manager service not running!\n"
            "This service is required for device isolation."
        )
        
        # Check service logs for permission grants
        logs = host.run("journalctl -u media-bridge-permission-manager -n 20 --no-pager")
        assert "Chrome" in logs.stdout, "Permission manager not handling Chrome"
        assert "GRANT" in logs.stdout or "DENY" in logs.stdout, (
            "Permission manager not making access decisions"
        )
    
    def test_unknown_apps_see_no_devices(self, host):
        """Unknown applications should see NO audio devices (deny by default)."""
        # Try to list devices as a test application
        test_result = host.run("""
            timeout 2 pw-cli ls Node 2>&1 | grep -E 'permission denied|no access|forbidden'
        """)
        
        # If we can't test directly, check default policy
        default_policy = host.run("""
            grep -r 'default.*permission.*""' /etc/wireplumber/ 2>/dev/null
        """)
        
        assert 'permission.*""' in default_policy.stdout or 'deny' in default_policy.stdout.lower(), (
            "Default policy is not deny-all!\n"
            "Unknown apps should see NO devices by default."
        )
    
    def test_no_watchdog_service_exists(self, host):
        """Watchdog service should not exist - we use permissions now."""
        watchdog_check = host.run("systemctl status media-bridge-audio-watchdog 2>&1")
        assert "could not be found" in watchdog_check.stdout or "not-found" in watchdog_check.stdout, (
            "Watchdog service still exists!\n"
            "With proper isolation, watchdog is not needed."
        )
        
        # Also check the script doesn't exist
        script_check = host.run("ls /usr/local/bin/media-bridge-audio-watchdog 2>&1")
        assert script_check.exit_status != 0, (
            "Watchdog script still exists!\n"
            "Should be removed with permission-based isolation."
        )
    
    def test_virtual_devices_exist_and_isolated(self, host):
        """Virtual devices must exist and be properly isolated."""
        # Check virtual devices exist using pw-cli
        devices = host.run("pw-cli ls Node | grep -E 'intercom-speaker|intercom-microphone'")
        assert devices.exit_status == 0, "Virtual devices not found"
        
        # Virtual speaker must exist
        speaker = host.run("pw-cli ls Node | grep 'intercom-speaker'")
        assert speaker.exit_status == 0, "intercom-speaker not found"
        
        # Virtual microphone must exist  
        mic = host.run("pw-cli ls Node | grep 'intercom-microphone'")
        assert mic.exit_status == 0, "intercom-microphone not found"
        
        # Check isolation - virtual devices should have restricted access
        speaker_info = host.run("pw-cli info intercom-speaker | grep -i permission")
        mic_info = host.run("pw-cli info intercom-microphone | grep -i permission")
        
        # Permissions should be set (not default/open)
        assert "permission" in speaker_info.stdout.lower() or speaker_info.exit_status == 0
        assert "permission" in mic_info.stdout.lower() or mic_info.exit_status == 0
    
    def test_audio_routing_uses_pw_link(self, host):
        """Audio routing should use pw-link, not pactl."""
        # Check for active links
        links = host.run("pw-link -l")
        assert links.exit_status == 0, "pw-link not working"
        
        # Check Chrome is linked to virtual devices
        chrome_links = host.run("pw-link -l | grep -i chrome")
        if chrome_links.exit_status == 0:
            assert "intercom-speaker" in chrome_links.stdout or "intercom-microphone" in chrome_links.stdout, (
                "Chrome not linked to virtual devices via pw-link"
            )
        
        # Check loopback links exist
        loopback_links = host.run("pw-link -l | grep -E 'intercom.*CSCTEK|CSCTEK.*intercom'")
        assert loopback_links.exit_status == 0, (
            "Loopback links between virtual and USB devices not found"
        )
    
    def test_chrome_audio_dropdown_filtered(self, host):
        """Chrome's audio device dropdown should ONLY show virtual devices."""
        # This test would ideally check Chrome's actual UI, but we can verify via logs
        chrome_log = host.run("""
            journalctl -u media-bridge-intercom -n 100 | grep -i 'enumerate.*device' || 
            journalctl | grep -i 'chrome.*enumerate' | tail -20
        """)
        
        # Check Chrome's device enumeration in PipeWire logs
        pw_log = host.run("""
            journalctl -u pipewire-system -n 50 | grep -i 'chrome.*permission' ||
            journalctl -u wireplumber-system -n 50 | grep -i 'chrome.*access'
        """)
        
        # At minimum, verify Chrome client has restricted access
        chrome_access = host.run("""
            pw-cli dump | grep -A10 'application.name = "Chrome"' | grep -i 'access\\|permission'
        """)
        
        assert "restricted" in chrome_access.stdout.lower() or "limited" in chrome_access.stdout.lower(), (
            "Chrome does not have restricted access!\n"
            "Chrome should have limited permissions for device filtering."
        )


class TestAudioFlowWithIsolation:
    """Test that audio still flows correctly with strict isolation."""
    
    def test_chrome_to_usb_audio_flow(self, host):
        """Audio flows: Chrome -> intercom-speaker -> USB output."""
        # Check Chrome is producing audio to virtual speaker
        chrome_output = host.run("""
            pw-cli ls Link | grep -B5 -A5 'Chrome' | grep 'intercom-speaker'
        """)
        
        assert chrome_output.exit_status == 0, (
            "Chrome not outputting to intercom-speaker"
        )
        
        # Check virtual speaker is linked to USB
        speaker_to_usb = host.run("""
            pw-link -l | grep -E 'intercom-speaker.*CSCTEK|intercom-speaker.*USB'
        """)
        
        assert speaker_to_usb.exit_status == 0, (
            "Virtual speaker not linked to USB output"
        )
    
    def test_usb_to_chrome_audio_flow(self, host):
        """Audio flows: USB input -> intercom-microphone -> Chrome."""
        # Check USB is linked to virtual microphone
        usb_to_mic = host.run("""
            pw-link -l | grep -E 'CSCTEK.*intercom-mic|USB.*intercom-mic'
        """)
        
        assert usb_to_mic.exit_status == 0, (
            "USB input not linked to virtual microphone"
        )
        
        # Check Chrome is receiving from virtual microphone
        chrome_input = host.run("""
            pw-cli ls Link | grep -B5 -A5 'Chrome' | grep 'intercom-microphone'
        """)
        
        assert chrome_input.exit_status == 0, (
            "Chrome not receiving from intercom-microphone"
        )
    
    def test_ndi_display_hdmi_output(self, host):
        """ndi-display outputs only to HDMI, isolated from intercom."""
        ndi_check = host.run("pgrep -f ndi-display")
        if ndi_check.exit_status != 0:
            pytest.skip("ndi-display not running")
        
        # Check ndi-display is linked to HDMI
        ndi_links = host.run("""
            pw-link -l | grep -i 'ndi-display' | grep -E 'hdmi|HDMI'
        """)
        
        assert ndi_links.exit_status == 0, (
            "ndi-display not outputting to HDMI"
        )
        
        # Verify ndi-display is NOT linked to intercom devices
        bad_links = host.run("""
            pw-link -l | grep -i 'ndi-display' | grep -i 'intercom'
        """)
        
        assert bad_links.exit_status != 0, (
            "ISOLATION VIOLATION: ndi-display is linked to intercom devices!"
        )