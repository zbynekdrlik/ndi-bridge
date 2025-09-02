"""
Comprehensive tests for Media Bridge Intercom core functionality.

Tests the complete intercom system including service, scripts, and basic operation.
"""

import pytest
import time
import json


class TestIntercomCore:
    """Core intercom service and script tests."""
    
    def test_intercom_service_exists(self, host):
        """Test that intercom service file exists."""
        service_file = host.file("/etc/systemd/system/media-bridge-intercom.service")
        assert service_file.exists, "Intercom service file should exist"
        assert service_file.user == "root"
        assert service_file.group == "root"
    
    def test_intercom_service_enabled(self, host):
        """Test that intercom service is enabled."""
        result = host.run("systemctl is-enabled media-bridge-intercom")
        assert result.stdout.strip() == "enabled", "Intercom service should be enabled"
    
    def test_intercom_service_running(self, host):
        """Test that intercom service is running."""
        service = host.service("media-bridge-intercom")
        assert service.is_running, "Intercom service should be running"
    
    def test_intercom_service_configuration(self, host):
        """Test that intercom service has correct configuration."""
        service_file = host.file("/etc/systemd/system/media-bridge-intercom.service")
        content = service_file.content_string
        
        # Check critical service settings
        assert "Restart=always" in content, "Service should have auto-restart"
        assert "RestartSec=" in content, "Service should have restart delay"
        assert "MemoryMax=" in content, "Service should have memory limit"
        assert "CPUQuota=" in content, "Service should have CPU limit"
        assert "WantedBy=multi-user.target" in content, "Service should start at boot"
    
    def test_intercom_launcher_script_exists(self, host):
        """Test that intercom launcher script exists and is executable."""
        script = host.file("/usr/local/bin/media-bridge-intercom-launcher")
        assert script.exists, "Launcher script should exist"
        assert script.mode & 0o111, "Launcher script should be executable"
        assert script.user == "root"
    
    def test_intercom_pipewire_script_exists(self, host):
        """Test that PipeWire implementation script exists."""
        script = host.file("/usr/local/bin/media-bridge-intercom-pipewire")
        assert script.exists, "PipeWire script should exist"
        assert script.mode & 0o111, "PipeWire script should be executable"
        
        # Verify it contains critical components
        content = script.content_string
        assert "pipewire" in content.lower(), "Should reference PipeWire"
        assert "chrome" in content.lower(), "Should reference Chrome"
        assert "vdo.ninja" in content.lower(), "Should reference VDO.Ninja"
    
    def test_intercom_control_script_exists(self, host):
        """Test that control script exists and is executable."""
        script = host.file("/usr/local/bin/media-bridge-intercom-control")
        assert script.exists, "Control script should exist"
        assert script.mode & 0o111, "Control script should be executable"
    
    def test_intercom_config_script_exists(self, host):
        """Test that config script exists and is executable."""
        script = host.file("/usr/local/bin/media-bridge-intercom-config")
        assert script.exists, "Config script should exist"
        assert script.mode & 0o111, "Config script should be executable"
    
    def test_intercom_monitor_script_exists(self, host):
        """Test that monitor script exists and is executable."""
        script = host.file("/usr/local/bin/media-bridge-intercom-monitor")
        assert script.exists, "Monitor script should exist"
        assert script.mode & 0o111, "Monitor script should be executable"
    
    def test_intercom_helper_scripts_exist(self, host):
        """Test that all helper scripts exist."""
        helper_scripts = [
            "media-bridge-intercom-status",
            "media-bridge-intercom-logs",
            "media-bridge-intercom-restart"
        ]
        
        for script_name in helper_scripts:
            script = host.file(f"/usr/local/bin/{script_name}")
            assert script.exists, f"{script_name} should exist"
            assert script.mode & 0o111, f"{script_name} should be executable"
    
    def test_intercom_status_command(self, host):
        """Test that status command works."""
        result = host.run("media-bridge-intercom-status")
        assert result.succeeded, "Status command should succeed"
        # Should show service status - check for key indicators
        assert "Service:" in result.stdout or "Chrome:" in result.stdout or "VNC:" in result.stdout
    
    def test_intercom_control_get_status(self, host):
        """Test that control script can get audio status."""
        result = host.run("media-bridge-intercom-control status")
        assert result.succeeded, "Control get command should succeed"
        
        # Should return JSON
        try:
            status = json.loads(result.stdout)
            assert "input" in status, "Should have input section"
            assert "output" in status, "Should have output section"
            assert "volume" in status["input"], "Should have input volume"
            assert "volume" in status["output"], "Should have output volume"
            assert "muted" in status["input"], "Should have input muted state"
            assert "muted" in status["output"], "Should have output muted state"
        except json.JSONDecodeError:
            pytest.fail(f"Control get should return valid JSON, got: {result.stdout}")
    
    @pytest.mark.slow
    @pytest.mark.timeout(90)  # Service restart takes 30-45s
    def test_intercom_service_restart(self, host):
        """Test that intercom service can be restarted."""
        # Get initial PID
        pid_before = host.run("systemctl show media-bridge-intercom --property MainPID").stdout.strip()
        pid_before = pid_before.split("=")[1] if "=" in pid_before else None
        
        # Restart service
        result = host.run("systemctl restart media-bridge-intercom")
        assert result.succeeded, "Service restart should succeed"
        
        # Wait for service to fully restart and stabilize
        time.sleep(35)
        
        # Check service is running
        service = host.service("media-bridge-intercom")
        assert service.is_running, "Service should be running after restart"
        
        # Wait for Chrome to fully start
        for _ in range(10):
            if host.run("pgrep -f google-chrome").succeeded:
                break
            time.sleep(2)
        
        # Check PID changed
        pid_after = host.run("systemctl show media-bridge-intercom --property MainPID").stdout.strip()
        pid_after = pid_after.split("=")[1] if "=" in pid_after else None
        
        if pid_before and pid_after and pid_before != "0":
            assert pid_before != pid_after, "Service PID should change after restart"
    
    def test_chrome_installed(self, host):
        """Test that Google Chrome is installed."""
        result = host.run("which google-chrome")
        assert result.succeeded, "Google Chrome should be installed"
        
        # Check it's executable
        chrome_path = result.stdout.strip()
        chrome_file = host.file(chrome_path)
        assert chrome_file.mode & 0o111, "Chrome should be executable"
    
    def test_pipewire_installed(self, host):
        """Test that PipeWire is installed."""
        result = host.run("which pipewire")
        assert result.succeeded, "PipeWire should be installed"
    
    def test_wireplumber_installed(self, host):
        """Test that WirePlumber is installed."""
        result = host.run("which wireplumber")
        assert result.succeeded, "WirePlumber should be installed"
    
    def test_xvfb_installed(self, host):
        """Test that Xvfb is installed for virtual display."""
        result = host.run("which Xvfb")
        assert result.succeeded, "Xvfb should be installed"
    
    def test_x11vnc_installed(self, host):
        """Test that x11vnc is installed for remote access."""
        result = host.run("which x11vnc")
        assert result.succeeded, "x11vnc should be installed"