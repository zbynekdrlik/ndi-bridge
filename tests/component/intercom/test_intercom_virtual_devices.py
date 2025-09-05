"""Test virtual device isolation for intercom Chrome audio security.

Tests for issue #34 (virtual device mapping) and #114 (HDMI security).
Ensures Chrome only uses virtual devices and never outputs to HDMI.
"""

import pytest
import time
import re


class TestIntercomVirtualDevices:
    """Test virtual device implementation and isolation."""

    def test_virtual_devices_exist_in_pipewire(self, host):
        """Test that virtual devices exist in PipeWire."""
        sinks = host.run("pactl list sinks short")
        assert sinks.exit_status == 0, "Failed to list sinks"
        
        # Check for virtual speaker sink
        assert "intercom-speaker" in sinks.stdout, (
            "Virtual intercom-speaker device not found in PipeWire sinks"
        )
        
        # Check for virtual microphone sink
        assert "intercom-microphone" in sinks.stdout, (
            "Virtual intercom-microphone device not found in PipeWire sinks"
        )
        
        # Check that monitor sources exist for the virtual sinks
        sources = host.run("pactl list sources short")
        assert sources.exit_status == 0, "Failed to list sources"
        
        assert "intercom-speaker.monitor" in sources.stdout, (
            "intercom-speaker monitor source not found"
        )
        assert "intercom-microphone.monitor" in sources.stdout, (
            "intercom-microphone monitor source not found"
        )

    def test_loopback_modules_active_with_usb(self, host):
        """Test loopback modules are active when USB audio connected."""
        modules = host.run("pactl list modules short")
        assert modules.exit_status == 0, "Failed to list modules"
        
        # Check if USB audio is connected (may show as CSCTEK or Zoran Co.)
        usb_devices = host.run("lsusb")
        has_usb_audio = ("CSCTEK" in usb_devices.stdout or 
                        "CSC" in usb_devices.stdout or
                        "USB Audio" in usb_devices.stdout or
                        "Zoran" in usb_devices.stdout)
        
        if has_usb_audio:
            # Should have loopback modules when USB connected
            assert "module-loopback" in modules.stdout, (
                "No loopback modules found despite USB audio connected"
            )
            
            # Check specific loopback configurations
            module_details = host.run("pactl list modules")
            
            # Virtual speaker to USB output loopback
            assert "source=intercom-speaker.monitor" in module_details.stdout, (
                "Missing loopback from virtual speaker to USB output"
            )
            
            # USB input to virtual microphone loopback
            assert "sink=intercom-microphone" in module_details.stdout, (
                "Missing loopback from USB input to virtual microphone"
            )
        else:
            pytest.skip("No CSCTEK USB audio device connected")

    def test_chrome_only_connects_to_virtual_devices(self, host):
        """Test Chrome ONLY connects to virtual devices, not hardware."""
        # Check if Chrome is running
        chrome_ps = host.run("pgrep -f 'chrome.*vdo.ninja'")
        if chrome_ps.exit_status != 0:
            pytest.skip("Chrome intercom not running")
        
        # Get all Chrome audio streams
        sink_inputs = host.run("pactl list sink-inputs")
        assert sink_inputs.exit_status == 0
        
        # Parse Chrome's sink connections
        chrome_sinks = []
        current_input = None
        is_chrome = False
        
        for line in sink_inputs.stdout.split('\n'):
            if "Sink Input #" in line:
                current_input = line.strip()
                is_chrome = False
            elif "application.name" in line and "Chrome" in line:
                is_chrome = True
            elif is_chrome and "Sink:" in line:
                # Extract sink ID
                sink_match = re.search(r'Sink:\s*(\d+)', line)
                if sink_match:
                    chrome_sinks.append(int(sink_match.group(1)))
        
        if chrome_sinks:
            # Get sink details to check what Chrome is connected to
            sinks_list = host.run("pactl list sinks")
            
            # Map sink IDs to names
            sink_names = {}
            current_sink_id = None
            
            for line in sinks_list.stdout.split('\n'):
                if "Sink #" in line:
                    id_match = re.search(r'Sink #(\d+)', line)
                    if id_match:
                        current_sink_id = int(id_match.group(1))
                elif current_sink_id and "Name:" in line:
                    name = line.split("Name:")[1].strip()
                    sink_names[current_sink_id] = name
            
            # Check Chrome's connections
            for sink_id in chrome_sinks:
                sink_name = sink_names.get(sink_id, "unknown")
                
                # Chrome should ONLY connect to virtual devices
                assert "intercom-speaker" in sink_name or "intercom-microphone" in sink_name, (
                    f"SECURITY: Chrome connected to non-virtual device: {sink_name} (ID: {sink_id})"
                )
                
                # Chrome should NEVER connect to HDMI
                assert "hdmi" not in sink_name.lower(), (
                    f"CRITICAL SECURITY: Chrome audio playing on HDMI: {sink_name}"
                )
                
                # Chrome should NEVER connect directly to USB
                assert "usb" not in sink_name.lower() and "CSCTEK" not in sink_name, (
                    f"Chrome directly connected to USB hardware: {sink_name}"
                )

    def test_no_audio_on_hdmi_from_intercom(self, host):
        """Test HDMI never receives intercom audio - critical security test."""
        # Get all sink inputs
        sink_inputs = host.run("pactl list sink-inputs")
        assert sink_inputs.exit_status == 0
        
        # Find HDMI sink ID
        sinks = host.run("pactl list sinks short")
        hdmi_sink_id = None
        
        for line in sinks.stdout.split('\n'):
            if 'hdmi' in line.lower():
                parts = line.split()
                if parts:
                    hdmi_sink_id = parts[0]
                    break
        
        if not hdmi_sink_id:
            pytest.skip("No HDMI audio sink found")
        
        # Check no intercom-related streams go to HDMI
        current_input = None
        sink_target = None
        is_intercom_related = False
        
        for line in sink_inputs.stdout.split('\n'):
            if "Sink Input #" in line:
                # Process previous input if it was intercom-related
                if is_intercom_related and sink_target == hdmi_sink_id:
                    pytest.fail(
                        f"CRITICAL SECURITY: Intercom audio routed to HDMI! {current_input}"
                    )
                
                # Reset for new input
                current_input = line.strip()
                is_intercom_related = False
                sink_target = None
                
            elif "Sink:" in line:
                sink_match = re.search(r'Sink:\s*(\d+)', line)
                if sink_match:
                    sink_target = sink_match.group(1)
                    
            elif any(keyword in line.lower() for keyword in 
                    ['chrome', 'intercom', 'vdo.ninja', 'media-bridge-monitor']):
                is_intercom_related = True
        
        # Check last input
        if is_intercom_related and sink_target == hdmi_sink_id:
            pytest.fail(
                f"CRITICAL SECURITY: Intercom audio routed to HDMI! {current_input}"
            )

    def test_virtual_devices_are_default_when_present(self, host):
        """Test virtual devices are set as defaults when created."""
        # Check default sink
        default_sink = host.run("pactl get-default-sink")
        if default_sink.exit_status == 0 and default_sink.stdout.strip():
            # When virtual devices exist, intercom-speaker should be default
            sinks = host.run("pactl list sinks short")
            if "intercom-speaker" in sinks.stdout:
                assert "intercom-speaker" in default_sink.stdout, (
                    f"Virtual speaker not default sink. Current: {default_sink.stdout.strip()}"
                )
        
        # Check default source  
        default_source = host.run("pactl get-default-source")
        if default_source.exit_status == 0 and default_source.stdout.strip():
            sources = host.run("pactl list sources short")
            if "intercom-microphone.monitor" in sources.stdout:
                assert "intercom-microphone" in default_source.stdout, (
                    f"Virtual microphone not default source. Current: {default_source.stdout.strip()}"
                )

    def test_chrome_uses_virtual_devices_not_hardware(self, host):
        """Test Chrome is actually using virtual devices for audio I/O."""
        # Ensure Chrome is running
        chrome_ps = host.run("pgrep -f 'chrome.*vdo.ninja'")
        if chrome_ps.exit_status != 0:
            pytest.skip("Chrome intercom not running")
        
        # Get Chrome's PipeWire connections
        pw_clients = host.run("pactl list clients")
        assert pw_clients.exit_status == 0
        
        # Find Chrome client details
        in_chrome_section = False
        chrome_props = []
        
        for line in pw_clients.stdout.split('\n'):
            if "Google Chrome" in line or "chrome" in line.lower():
                in_chrome_section = True
            elif in_chrome_section and "Client #" in line:
                in_chrome_section = False
            elif in_chrome_section:
                chrome_props.append(line)
        
        if chrome_props:
            props_text = '\n'.join(chrome_props)
            
            # Chrome should reference virtual devices in its properties
            if "node.target" in props_text or "target.object" in props_text:
                # Should target virtual devices
                assert "intercom" in props_text.lower(), (
                    "Chrome not configured to use virtual intercom devices"
                )

    def test_hardware_devices_hidden_from_chrome(self, host):
        """Test hardware audio devices are not accessible to Chrome."""
        # This test would ideally check Chrome's internal device enumeration
        # but that requires browser automation. Instead, we verify the
        # PipeWire/WirePlumber policy configuration
        
        # Check WirePlumber configuration exists
        wireplumber_conf = host.file("/etc/wireplumber/media-bridge.lua")
        if wireplumber_conf.exists:
            content = wireplumber_conf.content_string
            
            # Should have rules to restrict Chrome
            assert "chrome" in content.lower() or "intercom" in content.lower(), (
                "No Chrome/intercom specific rules in WirePlumber config"
            )
            
            # Should restrict access to hardware nodes
            if "access" in content.lower():
                assert "restricted" in content.lower() or "deny" in content.lower(), (
                    "No access restrictions for hardware devices"
                )

    @pytest.mark.slow
    def test_usb_hotplug_maintains_virtual_routing(self, host):
        """Test USB device hot-plug maintains virtual device routing."""
        # This test would require physical USB disconnect/reconnect
        # or simulation via kernel events. Mark as slow and optional.
        
        # Audio manager is integrated into intercom service, not standalone
        # Check if intercom service is configured to handle USB events
        intercom_service = host.service("media-bridge-intercom")
        if intercom_service.is_running:
            # Verify service is configured to restart and handle audio setup
            service_file = host.file("/etc/systemd/system/media-bridge-intercom.service")
            if service_file.exists:
                content = service_file.content_string
                
                # Should restart on failure to handle disconnects
                assert "Restart=" in content, (
                    "Intercom service not configured to restart on failure"
                )
                
                # Should setup audio devices on start
                assert "media-bridge-audio-manager setup" in content, (
                    "Intercom service doesn't setup audio devices"
                )
                
                # Should have PipeWire dependency
                assert "pipewire-system.service" in content, (
                    "Intercom service missing PipeWire dependency"
                )
        else:
            pytest.skip("Intercom service not running")

    def test_loopback_latency_configuration(self, host):
        """Test loopback modules have proper low-latency configuration."""
        modules = host.run("pactl list modules")
        assert modules.exit_status == 0
        
        # Find loopback modules and check their configuration
        loopback_configs = []
        current_module = None
        
        for line in modules.stdout.split('\n'):
            if "Name: module-loopback" in line:
                current_module = {}
            elif current_module is not None and "Argument:" in line:
                loopback_configs.append(line)
                current_module = None
        
        for config in loopback_configs:
            # Check for low latency setting (5ms or less)
            if "latency_msec=" in config:
                latency_match = re.search(r'latency_msec=(\d+)', config)
                if latency_match:
                    latency = int(latency_match.group(1))
                    assert latency <= 10, (
                        f"Loopback latency too high: {latency}ms (should be ≤10ms)"
                    )
            
            # Check for proper rate
            if "rate=" in config:
                rate_match = re.search(r'rate=(\d+)', config)
                if rate_match:
                    rate = int(rate_match.group(1))
                    assert rate >= 48000, (
                        f"Loopback sample rate too low: {rate} (should be ≥48000)"
                    )