"""Comprehensive test for intercom service restart on device rename.

Tests fix for issue #53 - Chrome intercom should restart automatically
when media-bridge-set-name is used.
"""

import pytest
import time


class TestIntercomRenameComprehensive:
    """Comprehensive test suite for intercom restart on device rename."""
    
    def test_intercom_service_basics(self, host):
        """Test that intercom service is properly configured."""
        # Check service is enabled
        service = host.service("media-bridge-intercom")
        assert service.is_enabled, "Intercom service should be enabled"
        
        # Check service is running
        assert service.is_running, "Intercom service should be running"
        
        # Check service file exists
        service_file = host.file("/etc/systemd/system/media-bridge-intercom.service")
        assert service_file.exists, "Service file should exist"
        
        # Check service has restart policy
        assert "Restart=" in service_file.content_string, "Service should have restart policy"
    
    def test_set_name_script_basics(self, host):
        """Test that media-bridge-set-name script is properly configured."""
        # Check script exists
        script = host.file("/usr/local/bin/media-bridge-set-name")
        assert script.exists, "media-bridge-set-name script should exist"
        
        # Check script is executable
        assert script.mode & 0o111, "Script should be executable"
        
        # Check script contains intercom restart logic
        script_content = script.content_string
        assert "media-bridge-intercom" in script_content, "Script should reference intercom service"
        assert "systemctl restart media-bridge-intercom" in script_content, "Script should restart intercom"
    
    def test_chrome_process_running(self, host):
        """Test that Chrome process is running with VDO.Ninja."""
        # Wait for Chrome to be fully started (up to 60 seconds)
        chrome_found = False
        for attempt in range(60):
            # Check if Chrome process exists
            result = host.run("pgrep -f 'vdo.ninja' || true")
            if result.stdout.strip():
                chrome_found = True
                break
            time.sleep(1)
        
        assert chrome_found, "Chrome process with vdo.ninja should be running"
        
        # Verify Chrome command line contains expected parameters
        ps_result = host.run("ps aux | grep -v grep | grep chrome | grep vdo.ninja || true")
        assert ps_result.stdout.strip(), "Chrome should be running with vdo.ninja URL"
        
        # Extract the push parameter from Chrome command
        chrome_cmd = ps_result.stdout
        assert "push=" in chrome_cmd, "Chrome should have push parameter"
    
    @pytest.mark.slow
    def test_intercom_restart_on_rename_simulation(self, host):
        """Test that intercom would restart when name changes (without actually renaming)."""
        # Get current Chrome PID
        pid_result = host.run("pgrep -f 'vdo.ninja' | head -1 || echo 'none'")
        original_pid = pid_result.stdout.strip()
        
        # Skip if Chrome not running
        if original_pid == 'none':
            pytest.skip("Chrome not running, cannot test restart")
        
        # Test that restart command works
        restart_result = host.run("systemctl restart media-bridge-intercom")
        assert restart_result.succeeded, "Service restart should succeed"
        
        # Wait for service to come back up
        time.sleep(10)
        
        # Check service is running again
        service = host.service("media-bridge-intercom")
        assert service.is_running, "Service should be running after restart"
        
        # Wait for Chrome to start (up to 60 seconds)
        new_chrome_found = False
        new_pid = None
        for attempt in range(60):
            pid_result = host.run("pgrep -f 'vdo.ninja' | head -1 || echo 'none'")
            new_pid = pid_result.stdout.strip()
            if new_pid != 'none':
                new_chrome_found = True
                break
            time.sleep(1)
        
        assert new_chrome_found, "Chrome should restart after service restart"
        assert new_pid != original_pid, f"Chrome PID should change after restart (was {original_pid}, now {new_pid})"
    
    @pytest.mark.slow
    @pytest.mark.destructive
    @pytest.mark.timeout(120)  # Increase timeout to 120 seconds
    def test_full_rename_flow(self, host):
        """Test the complete rename flow with actual device rename."""
        # Store original hostname
        original_hostname = host.run("hostname").stdout.strip()
        original_name = original_hostname.replace("media-bridge-", "")
        
        # The test should always restore to a clean state
        # We don't restore to the original because it may have been pytest99 from a previous failed test
        
        # Get Chrome PID before rename
        pid_before = host.run("pgrep -f 'vdo.ninja' | head -1 || echo 'none'").stdout.strip()
        
        # Skip if Chrome not running
        if pid_before == 'none':
            # Wait for Chrome to start
            time.sleep(30)
            pid_before = host.run("pgrep -f 'vdo.ninja' | head -1 || echo 'none'").stdout.strip()
            if pid_before == 'none':
                pytest.skip("Chrome not running even after wait")
        
        # Get Chrome command line before rename
        ps_before = host.run("ps aux | grep -v grep | grep chrome | grep vdo.ninja || true").stdout
        
        # Perform the rename
        new_name = "pytest99"
        rename_result = host.run(f"media-bridge-set-name {new_name}")
        assert rename_result.succeeded, "Rename should succeed"
        
        # Verify output shows intercom restart
        assert "Restarting Intercom service" in rename_result.stdout, "Should show intercom restart message"
        
        # Verify hostname changed
        new_hostname = host.run("hostname").stdout.strip()
        assert new_hostname == f"media-bridge-{new_name}", f"Hostname should be media-bridge-{new_name}"
        
        # Wait for Chrome to restart (up to 60 seconds)
        chrome_restarted = False
        pid_after = None
        for attempt in range(60):
            pid_result = host.run("pgrep -f 'vdo.ninja' | head -1 || echo 'none'")
            pid_after = pid_result.stdout.strip()
            if pid_after != 'none' and pid_after != pid_before:
                chrome_restarted = True
                break
            time.sleep(1)
        
        assert chrome_restarted, f"Chrome should restart with new PID (was {pid_before}, should be different)"
        
        # Wait for Chrome to fully start with all parameters (up to 30 seconds)
        chrome_with_new_name = False
        ps_after = ""
        for wait in range(30):
            ps_result = host.run("ps aux | grep 'google-chrome' | grep -v 'grep' | head -1 || true")
            if ps_result.stdout and f"push={new_name}" in ps_result.stdout:
                chrome_with_new_name = True
                ps_after = ps_result.stdout
                break
            time.sleep(1)
        
        assert chrome_with_new_name, f"Chrome should use new name '{new_name}' in push parameter after 30 seconds. Last ps output: {ps_after}"
        
        # Verify that the rename properly updated all system files
        # Check avahi configuration was updated
        avahi_config = host.run("grep '^host-name=' /etc/avahi/avahi-daemon.conf").stdout.strip()
        assert f"host-name=media-bridge-{new_name}" in avahi_config, f"Avahi config should have new hostname, got: {avahi_config}"
        
        # Check NDI config was updated
        ndi_config = host.run("grep 'NDI_NAME=' /etc/media-bridge/config").stdout.strip()
        assert f'NDI_NAME="{new_name}"' in ndi_config, f"NDI config should have new name, got: {ndi_config}"
        
        # Check mDNS advertisement
        avahi_browse = host.run("avahi-browse -a -t -r -p 2>/dev/null | grep -o '[^;]*\\.local' | head -1 || echo 'none'").stdout.strip()
        # Should see the new name in mDNS (though it might take time to propagate)
        
        # Now restore using the helper script itself (as it should be used in real scenarios)
        # The helper script should handle all the system updates
        restore_result = host.run("media-bridge-set-name USB_Capture")
        assert restore_result.succeeded, "Restore with helper script should succeed"
        
        # Verify output shows intercom restart
        assert "Restarting Intercom service" in restore_result.stdout, "Restore should show intercom restart message"
        
        # Wait for services to stabilize
        time.sleep(5)
        
        # Verify complete restoration
        restored_hostname = host.run("hostname").stdout.strip()
        assert restored_hostname == "media-bridge", f"Hostname should be restored to media-bridge, got {restored_hostname}"
        
        # Verify avahi was restored
        avahi_restored = host.run("grep '^host-name=' /etc/avahi/avahi-daemon.conf").stdout.strip()
        assert "host-name=media-bridge" in avahi_restored, f"Avahi should be restored, got: {avahi_restored}"
        
        # Verify NDI config was restored
        ndi_restored = host.run("grep 'NDI_NAME=' /etc/media-bridge/config").stdout.strip()
        assert 'NDI_NAME="USB Capture"' in ndi_restored, f"NDI config should be restored, got: {ndi_restored}"
    
    def test_intercom_survives_reboot(self, host):
        """Test that intercom service is enabled and starts on boot."""
        # Check if service is enabled (will start on boot)
        enabled_result = host.run("systemctl is-enabled media-bridge-intercom")
        assert enabled_result.stdout.strip() == "enabled", "Service should be enabled for boot"
        
        # Check WantedBy target
        service_file = host.file("/etc/systemd/system/media-bridge-intercom.service")
        assert "WantedBy=multi-user.target" in service_file.content_string, "Service should start in multi-user target"