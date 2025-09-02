"""
Integration tests for NDI Bridge Intercom.

Tests complete workflows and feature interactions.
"""

import pytest
import json
import time


class TestIntercomIntegration:
    """Integration tests for complete intercom workflows."""
    
    @pytest.mark.slow
    @pytest.mark.integration
    def test_complete_audio_workflow(self, host):
        """Test complete audio configuration workflow."""
        # Get initial state
        result = host.run("ndi-bridge-intercom-control get")
        initial_state = json.loads(result.stdout)
        
        try:
            # Test volume adjustment workflow
            test_volumes = [40, 60, 80]
            
            for volume in test_volumes:
                # Set mic volume
                result = host.run(f"ndi-bridge-intercom-control set mic_volume {volume}")
                assert result.succeeded, f"Should set mic volume to {volume}"
                
                # Set speaker volume
                result = host.run(f"ndi-bridge-intercom-control set speaker_volume {volume}")
                assert result.succeeded, f"Should set speaker volume to {volume}"
                
                # Verify both changed
                result = host.run("ndi-bridge-intercom-control get")
                current = json.loads(result.stdout)
                assert current["mic_volume"] == volume
                assert current["speaker_volume"] == volume
            
            # Test mute workflow
            host.run("ndi-bridge-intercom-control mute mic")
            result = host.run("ndi-bridge-intercom-control get")
            current = json.loads(result.stdout)
            assert current["mic_muted"] == True
            
            # Unmute
            host.run("ndi-bridge-intercom-control unmute mic")
            result = host.run("ndi-bridge-intercom-control get")
            current = json.loads(result.stdout)
            assert current["mic_muted"] == False
            
        finally:
            # Restore initial state
            host.run(f"ndi-bridge-intercom-control set mic_volume {initial_state['mic_volume']}")
            host.run(f"ndi-bridge-intercom-control set speaker_volume {initial_state['speaker_volume']}")
            if initial_state["mic_muted"]:
                host.run("ndi-bridge-intercom-control mute mic")
    
    @pytest.mark.slow
    @pytest.mark.integration
    def test_monitor_workflow(self, host):
        """Test complete monitor (self-hearing) workflow."""
        # Get initial state
        result = host.run("ndi-bridge-intercom-control get")
        initial_state = json.loads(result.stdout)
        
        try:
            # Enable monitor
            result = host.run("ndi-bridge-intercom-monitor enable")
            assert result.succeeded, "Should enable monitor"
            
            # Wait for PipeWire module to load
            time.sleep(3)
            
            # Check monitor is enabled
            result = host.run("ndi-bridge-intercom-control get")
            current = json.loads(result.stdout)
            assert current["monitor_enabled"] == True
            
            # Adjust monitor level
            result = host.run("ndi-bridge-intercom-control set monitor_level 50")
            assert result.succeeded, "Should set monitor level"
            
            # Verify level changed
            result = host.run("ndi-bridge-intercom-control get")
            current = json.loads(result.stdout)
            assert current["monitor_level"] == 50
            
            # Disable monitor
            result = host.run("ndi-bridge-intercom-monitor disable")
            assert result.succeeded, "Should disable monitor"
            
            time.sleep(3)
            
            # Check monitor is disabled
            result = host.run("ndi-bridge-intercom-control get")
            current = json.loads(result.stdout)
            assert current["monitor_enabled"] == False
            
        finally:
            # Restore initial state
            if initial_state["monitor_enabled"]:
                host.run("ndi-bridge-intercom-monitor enable")
            else:
                host.run("ndi-bridge-intercom-monitor disable")
            host.run(f"ndi-bridge-intercom-control set monitor_level {initial_state['monitor_level']}")
    
    @pytest.mark.slow
    @pytest.mark.integration
    def test_configuration_persistence_workflow(self, host):
        """Test complete configuration save/load workflow."""
        # Get initial state
        result = host.run("ndi-bridge-intercom-control get")
        initial_state = json.loads(result.stdout)
        
        # Make filesystem writable
        host.run("ndi-bridge-rw")
        
        try:
            # Create test configuration
            test_config = {
                "mic_volume": 55,
                "speaker_volume": 65,
                "monitor_level": 45,
                "monitor_enabled": True
            }
            
            # Apply test configuration
            host.run(f"ndi-bridge-intercom-control set mic_volume {test_config['mic_volume']}")
            host.run(f"ndi-bridge-intercom-control set speaker_volume {test_config['speaker_volume']}")
            host.run(f"ndi-bridge-intercom-control set monitor_level {test_config['monitor_level']}")
            if test_config['monitor_enabled']:
                host.run("ndi-bridge-intercom-monitor enable")
            
            # Save configuration
            result = host.run("ndi-bridge-intercom-config save")
            assert result.succeeded, "Should save configuration"
            
            # Change to different values
            host.run("ndi-bridge-intercom-control set mic_volume 90")
            host.run("ndi-bridge-intercom-control set speaker_volume 95")
            host.run("ndi-bridge-intercom-monitor disable")
            
            # Load saved configuration
            result = host.run("ndi-bridge-intercom-config load")
            assert result.succeeded, "Should load configuration"
            
            # Wait for settings to apply
            time.sleep(2)
            
            # Verify configuration restored
            result = host.run("ndi-bridge-intercom-control get")
            current = json.loads(result.stdout)
            
            assert current["mic_volume"] == test_config["mic_volume"]
            assert current["speaker_volume"] == test_config["speaker_volume"]
            assert current["monitor_level"] == test_config["monitor_level"]
            
        finally:
            # Restore initial configuration
            host.run(f"ndi-bridge-intercom-control set mic_volume {initial_state['mic_volume']}")
            host.run(f"ndi-bridge-intercom-control set speaker_volume {initial_state['speaker_volume']}")
            host.run(f"ndi-bridge-intercom-control set monitor_level {initial_state['monitor_level']}")
            if initial_state["monitor_enabled"]:
                host.run("ndi-bridge-intercom-monitor enable")
            else:
                host.run("ndi-bridge-intercom-monitor disable")
            
            # Save restored configuration
            host.run("ndi-bridge-intercom-config save")
            
            # Return to read-only
            host.run("ndi-bridge-ro")
    
    @pytest.mark.slow
    @pytest.mark.integration
    def test_service_restart_recovery(self, host):
        """Test that intercom recovers properly after service restart."""
        # Get current settings
        result = host.run("ndi-bridge-intercom-control get")
        settings_before = json.loads(result.stdout)
        
        # Check Chrome PID before restart
        chrome_pid_before = host.run("pgrep -f 'google-chrome' | head -1").stdout.strip()
        
        # Restart service
        result = host.run("systemctl restart ndi-bridge-intercom")
        assert result.succeeded, "Service restart should succeed"
        
        # Wait for service to fully start
        time.sleep(15)
        
        # Check service is running
        service = host.service("ndi-bridge-intercom")
        assert service.is_running, "Service should be running after restart"
        
        # Check Chrome is running with new PID
        chrome_pid_after = host.run("pgrep -f 'google-chrome' | head -1").stdout.strip()
        if chrome_pid_before and chrome_pid_after:
            assert chrome_pid_before != chrome_pid_after, "Chrome should have new PID"
        
        # Check settings preserved
        result = host.run("ndi-bridge-intercom-control get")
        settings_after = json.loads(result.stdout)
        
        assert settings_after["mic_volume"] == settings_before["mic_volume"]
        assert settings_after["speaker_volume"] == settings_before["speaker_volume"]
        
        # Check all processes running
        assert host.run("pgrep pipewire").succeeded, "PipeWire should be running"
        assert host.run("pgrep wireplumber").succeeded, "WirePlumber should be running"
        assert host.run("pgrep Xvfb").succeeded, "Xvfb should be running"
        assert host.run("pgrep x11vnc").succeeded, "x11vnc should be running"
    
    @pytest.mark.slow
    @pytest.mark.integration
    def test_vnc_remote_access(self, host):
        """Test that VNC remote access is working."""
        # Check VNC is listening
        result = host.run("ss -tlnp | grep :5999")
        assert result.succeeded, "VNC should be listening on port 5999"
        
        # Test VNC connection (without actually connecting)
        result = host.run("nc -zv localhost 5999 2>&1")
        assert "succeeded" in result.stdout.lower() or "connected" in result.stdout.lower()
        
        # Check display is set correctly
        result = host.run("ps aux | grep -v grep | grep x11vnc")
        assert ":99" in result.stdout, "VNC should use display :99"
    
    @pytest.mark.slow
    @pytest.mark.integration
    def test_vdo_ninja_connection(self, host):
        """Test that Chrome connects to VDO.Ninja correctly."""
        # Check Chrome is running
        result = host.run("ps aux | grep -v grep | grep google-chrome")
        assert result.succeeded, "Chrome should be running"
        
        chrome_cmd = result.stdout
        
        # Verify VDO.Ninja parameters
        assert "vdo.ninja" in chrome_cmd.lower(), "Should connect to VDO.Ninja"
        assert "room=nl_interkom" in chrome_cmd, "Should use nl_interkom room"
        
        # Get hostname for push parameter
        hostname = host.run("hostname").stdout.strip()
        device_name = hostname.replace("ndi-bridge-", "")
        assert f"push={device_name}" in chrome_cmd, f"Should use device name '{device_name}'"
        
        # Check Chrome profile directory exists
        assert host.file("/tmp/chrome-vdo-profile").exists or \
               host.file("/tmp/chrome-data").exists, "Chrome profile directory should exist"
    
    @pytest.mark.requires_usb
    @pytest.mark.integration
    def test_usb_audio_integration(self, host):
        """Test USB audio device integration."""
        # Check USB audio device is present
        result = host.run("aplay -l | grep -i 'usb\\|CSCTEK'")
        if not result.succeeded:
            pytest.skip("No USB audio device connected")
        
        # Check PipeWire sees the device
        result = host.run("pw-cli list-objects | grep -i 'usb\\|csctek' | head -5")
        assert result.succeeded or result.stdout, "PipeWire should see USB audio device"
        
        # Check audio routing is possible
        result = host.run("pactl list sinks | grep -i 'usb\\|csctek'")
        assert result.succeeded or result.stdout, "USB audio should be available as sink"
        
        result = host.run("pactl list sources | grep -i 'usb\\|csctek'")
        assert result.succeeded or result.stdout, "USB audio should be available as source"