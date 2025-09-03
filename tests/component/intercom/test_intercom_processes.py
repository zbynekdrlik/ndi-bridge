"""
Tests for Media Bridge Intercom process management and runtime behavior.

Verifies that all intercom processes are running correctly.
"""

import pytest
import time
import re


class TestIntercomProcesses:
    """Test intercom runtime processes."""
    
    @pytest.mark.slow
    def test_chrome_process_running(self, host):
        """Test that Chrome process is running with correct parameters."""
        # Wait for Chrome to be running (up to 60 seconds)
        chrome_found = False
        chrome_ps = None
        
        for attempt in range(60):
            result = host.run("ps aux | grep -v grep | grep google-chrome")
            if result.succeeded and result.stdout.strip():
                chrome_found = True
                chrome_ps = result.stdout
                break
            time.sleep(1)
        
        assert chrome_found, "Chrome process should be running"
        
        # Verify Chrome parameters
        assert "--no-sandbox" in chrome_ps, "Chrome should run with no-sandbox"
        assert "--disable-gpu" in chrome_ps, "Chrome should disable GPU"
        assert "vdo.ninja" in chrome_ps.lower(), "Chrome should connect to VDO.Ninja"
    
    def test_chrome_vdo_ninja_parameters(self, host):
        """Test that Chrome is using correct VDO.Ninja parameters."""
        result = host.run("ps aux | grep -v grep | grep google-chrome")
        assert result.succeeded, "Chrome should be running for intercom"
        
        chrome_cmd = result.stdout
        
        # Check VDO.Ninja parameters
        assert "room=nl_interkom" in chrome_cmd, "Should use nl_interkom room"
        assert "push=" in chrome_cmd, "Should have push parameter"
        assert "miconly" in chrome_cmd or "novideo" in chrome_cmd, "Should be audio-only"
        assert "autostart" in chrome_cmd, "Should auto-start"
    
    def test_xvfb_process_running(self, host):
        """Test that Xvfb virtual display is running."""
        result = host.run("pgrep -f Xvfb")
        assert result.succeeded, "Xvfb should be running"
        
        # Check display configuration
        ps_result = host.run("ps aux | grep -v grep | grep Xvfb")
        assert ":99" in ps_result.stdout, "Xvfb should use display :99"
    
    def test_x11vnc_process_running(self, host):
        """Test that x11vnc is running for remote access."""
        result = host.run("pgrep -f x11vnc")
        assert result.succeeded, "x11vnc should be running"
        
        # Check VNC configuration
        ps_result = host.run("ps aux | grep -v grep | grep x11vnc")
        assert ":99" in ps_result.stdout, "x11vnc should use display :99"
        assert "5999" in ps_result.stdout, "x11vnc should use port 5999"
    
    def test_pipewire_process_running(self, host):
        """Test that PipeWire is running."""
        result = host.run("pgrep pipewire")
        assert result.succeeded, "PipeWire should be running"
    
    def test_wireplumber_process_running(self, host):
        """Test that WirePlumber is running."""
        result = host.run("pgrep wireplumber")
        assert result.succeeded, "WirePlumber should be running"
    
    def test_vnc_port_listening(self, host):
        """Test that VNC port 5999 is listening."""
        result = host.run("ss -tlnp | grep :5999")
        assert result.succeeded, "Port 5999 should be listening"
        assert "x11vnc" in result.stdout.lower(), "x11vnc should be listening on port 5999"
    
    def test_display_environment_set(self, host):
        """Test that DISPLAY environment is set correctly."""
        # Check in the intercom process environment
        result = host.run("systemctl show media-bridge-intercom --property Environment")
        if "DISPLAY" in result.stdout:
            assert "DISPLAY=:99" in result.stdout or "DISPLAY=\":99\"" in result.stdout
    
    def test_chrome_using_correct_display(self, host):
        """Test that Chrome is using the virtual display."""
        result = host.run("ps aux | grep -v grep | grep google-chrome")
        assert result.succeeded, "Chrome should be running for intercom"
        
        # Get Chrome PID
        chrome_pid = result.stdout.split()[1]
        
        # Check environment
        env_result = host.run(f"cat /proc/{chrome_pid}/environ 2>/dev/null | tr '\\0' '\\n' | grep DISPLAY")
        if env_result.succeeded:
            assert ":99" in env_result.stdout, "Chrome should use display :99"
    
    def test_chrome_profile_directory(self, host):
        """Test that Chrome is using correct profile directory."""
        result = host.run("ps aux | grep -v grep | grep google-chrome")
        assert result.succeeded, "Chrome should be running for intercom"
        
        chrome_cmd = result.stdout
        assert "--user-data-dir=" in chrome_cmd, "Chrome should have user data dir"
        assert "/tmp/chrome" in chrome_cmd, "Chrome should use /tmp for profile"
    
    @pytest.mark.slow
    def test_chrome_restart_recovery(self, host):
        """Test that Chrome recovers after being killed."""
        # Get initial Chrome PID
        result = host.run("pgrep -f 'google-chrome' | head -1")
        if not result.succeeded:
            pytest.skip("Chrome not running")
        
        initial_pid = result.stdout.strip()
        
        # Kill Chrome
        host.run(f"kill -9 {initial_pid}")
        
        # Wait for Chrome to restart (service should restart it)
        chrome_restarted = False
        new_pid = None
        
        for attempt in range(60):
            result = host.run("pgrep -f 'google-chrome' | head -1")
            if result.succeeded:
                new_pid = result.stdout.strip()
                if new_pid != initial_pid:
                    chrome_restarted = True
                    break
            time.sleep(1)
        
        assert chrome_restarted, "Chrome should restart after being killed"
    
    def test_process_resource_usage(self, host):
        """Test that intercom processes are not using excessive resources."""
        # Check Chrome memory usage
        result = host.run("ps aux | grep -v grep | grep google-chrome | head -1")
        if result.succeeded and result.stdout:
            fields = result.stdout.split()
            if len(fields) > 3:
                mem_percent = float(fields[3])
                assert mem_percent < 20, f"Chrome using too much memory: {mem_percent}%"
        
        # Check overall intercom service memory
        result = host.run("systemctl show media-bridge-intercom --property MemoryCurrent")
        if "MemoryCurrent=" in result.stdout:
            mem_bytes = result.stdout.split("=")[1].strip()
            if mem_bytes and mem_bytes != "[not set]":
                mem_mb = int(mem_bytes) / (1024 * 1024)
                assert mem_mb < 512, f"Intercom service using too much memory: {mem_mb}MB"
    
    def test_chrome_push_parameter_matches_hostname(self, host):
        """Test that Chrome push parameter matches device hostname."""
        # Get hostname
        hostname = host.run("hostname").stdout.strip()
        device_name = hostname.replace("media-bridge-", "")
        
        # Wait for Chrome to be running (especially after service restarts)
        chrome_found = False
        chrome_cmd = ""
        
        for attempt in range(30):  # Up to 90 seconds total
            result = host.run("ps aux | grep -v grep | grep google-chrome")
            if result.succeeded and result.stdout.strip():
                chrome_found = True
                chrome_cmd = result.stdout
                break
            time.sleep(3)  # Wait 3s between attempts
        
        assert chrome_found, "Chrome should be running for intercom"
        assert f"push={device_name}" in chrome_cmd, f"Chrome should use device name '{device_name}' as push parameter"