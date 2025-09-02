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
    @pytest.mark.timeout(120)  # Service restart takes 45-50s total, 120s for safety
    def test_service_restart_recovery(self, host):
        """Test that intercom recovers properly after service restart (30s expected)."""        
        # Get current settings
        result = host.run("media-bridge-intercom-control status")
        assert result.succeeded, f"Failed to get initial status: {result.stderr}"
        settings_before = json.loads(result.stdout)
        
        # Check Chrome PID before restart
        chrome_result = host.run("pgrep -f 'google-chrome' | head -1")
        chrome_pid_before = chrome_result.stdout.strip()
        
        # Restart service
        result = host.run("systemctl restart media-bridge-intercom")
        assert result.succeeded, f"Service restart failed: {result.stderr}"
        
        # Wait for service to fully start (30s is expected)
        time.sleep(35)
        
        # Check service is running
        service = host.service("media-bridge-intercom")
        assert service.is_running, "Service should be running after restart"
        
        # Check Chrome is running with new PID
        chrome_result = host.run("pgrep -f 'google-chrome' | head -1")
        chrome_pid_after = chrome_result.stdout.strip()
        
        if chrome_pid_before and chrome_pid_after:
            assert chrome_pid_before != chrome_pid_after, f"Chrome PID unchanged: {chrome_pid_before}"
        elif not chrome_pid_after:
            # Chrome might still be starting, wait more
            time.sleep(10)
            chrome_result = host.run("pgrep -f 'google-chrome' | head -1")
            chrome_pid_after = chrome_result.stdout.strip()
            assert chrome_pid_after, "Chrome should be running after restart"
        
        # Check settings preserved
        result = host.run("media-bridge-intercom-control status")
        assert result.succeeded, f"Failed to get status after restart: {result.stderr}"
        settings_after = json.loads(result.stdout)
        
        assert settings_after["input"]["volume"] == settings_before["input"]["volume"], \
            f"Input volume changed: {settings_before['input']['volume']} -> {settings_after['input']['volume']}"
        assert settings_after["output"]["volume"] == settings_before["output"]["volume"], \
            f"Output volume changed: {settings_before['output']['volume']} -> {settings_after['output']['volume']}"
        
        # Check all processes running
        assert host.run("pgrep pipewire").succeeded, "PipeWire should be running"
        assert host.run("pgrep wireplumber").succeeded, "WirePlumber should be running"
        assert host.run("pgrep Xvfb").succeeded, "Xvfb should be running"
        assert host.run("pgrep x11vnc").succeeded, "x11vnc should be running"
    
    @pytest.mark.slow
    @pytest.mark.integration
    def test_vnc_remote_access(self, host):
        """Test that VNC remote access is working (critical for support)."""
        # Check x11vnc is running
        result = host.run("pgrep -f x11vnc")
        assert result.succeeded, "x11vnc process should be running"
        
        # Check VNC is listening on port 5999
        result = host.run("ss -tlnp | grep :5999")
        assert result.succeeded, "VNC should be listening on port 5999"
        assert "x11vnc" in result.stdout.lower(), "x11vnc should be listening on port 5999"
        
        # Verify display configuration
        result = host.run("ps aux | grep -v grep | grep x11vnc")
        assert ":99" in result.stdout, "x11vnc should use display :99"
    
    @pytest.mark.slow
    @pytest.mark.integration
    def test_vdo_ninja_connection(self, host):
        """Test that Chrome connects to VDO.Ninja correctly."""
        # Chrome is critical - it must be running
        result = host.run("ps aux | grep -v grep | grep google-chrome")
        assert result.succeeded, "Chrome must be running for intercom to work"
        
        chrome_cmd = result.stdout
        
        # Verify VDO.Ninja parameters
        assert "vdo.ninja" in chrome_cmd.lower(), "Should connect to VDO.Ninja"
        assert "room=nl_interkom" in chrome_cmd, "Should use nl_interkom room"
        
        # Get hostname for push parameter
        hostname = host.run("hostname").stdout.strip()
        device_name = hostname.replace("media-bridge-", "")
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