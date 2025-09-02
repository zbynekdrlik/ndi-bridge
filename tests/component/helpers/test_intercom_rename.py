"""Test that intercom service restarts when device name changes.

Tests fix for issue #53 - Chrome intercom should restart automatically
when ndi-bridge-set-name is used.
"""

import pytest
import time
import random
import string


class TestIntercomRename:
    """Test suite for intercom restart on device rename."""
    
    @pytest.fixture(autouse=True)
    def setup(self, host):
        """Store original hostname for restoration."""
        self.original_hostname = host.run("hostname").stdout.strip()
        self.original_name = self.original_hostname.replace("ndi-bridge-", "")
        
        # Generate random test name
        suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
        self.test_name = f"test{suffix}"
        
        yield
        
        # Restore original name after test (skip if already set correctly)
        try:
            current_hostname = host.run("hostname").stdout.strip()
            if current_hostname != self.original_hostname:
                host.run(f"ndi-bridge-rw")
                host.run(f"ndi-bridge-set-name {self.original_name}")
                host.run(f"ndi-bridge-ro")
        except Exception:
            # If teardown fails, don't block test results
            pass
    
    
    def test_intercom_service_is_enabled(self, host):
        """Test that intercom service is enabled."""
        service = host.service("ndi-bridge-intercom")
        assert service.is_enabled
    
    @pytest.mark.slow
    def test_intercom_service_is_running(self, host):
        """Test that intercom service is running."""
        service = host.service("ndi-bridge-intercom")
        assert service.is_running
    
    @pytest.mark.slow
    def test_chrome_process_exists_before_rename(self, host):
        """Test that Chrome process is running before rename."""
        # Wait for Chrome to fully start (service may have just restarted)
        for i in range(30):  # Wait up to 30 seconds
            result = host.run("pgrep -f 'vdo.ninja'")
            if result.succeeded:
                break
            time.sleep(1)
        assert result.succeeded, "Chrome process with vdo.ninja not found after 30 seconds"
        assert result.stdout.strip() != ""
    
    def test_set_name_command_exists(self, host):
        """Test that ndi-bridge-set-name command exists."""
        assert host.file("/usr/local/bin/ndi-bridge-set-name").exists
    
    def test_set_name_command_is_executable(self, host):
        """Test that ndi-bridge-set-name is executable."""
        file = host.file("/usr/local/bin/ndi-bridge-set-name")
        assert file.mode & 0o111  # Check execute permission
    
    @pytest.mark.slow
    @pytest.mark.destructive
    def test_set_name_changes_hostname(self, host):
        """Test that ndi-bridge-set-name changes the hostname."""
        # Make filesystem writable
        host.run("ndi-bridge-rw")
        
        # Run set-name command
        result = host.run(f"ndi-bridge-set-name {self.test_name}")
        assert result.succeeded
        
        # Check hostname changed
        new_hostname = host.run("hostname").stdout.strip()
        assert new_hostname == f"ndi-bridge-{self.test_name}"
        
        # Return to read-only
        host.run("ndi-bridge-ro")
    
    @pytest.mark.slow
    @pytest.mark.destructive
    def test_set_name_restarts_intercom_service(self, host):
        """Test that ndi-bridge-set-name restarts intercom service."""
        # Make filesystem writable
        host.run("ndi-bridge-rw")
        
        # Get Chrome PID before rename
        result_before = host.run("pgrep -f 'vdo.ninja' | head -1")
        pid_before = result_before.stdout.strip() if result_before.succeeded else None
        
        # Run set-name command
        result = host.run(f"ndi-bridge-set-name {self.test_name}")
        assert result.succeeded
        
        # Check for restart message in output
        assert "Restarting Intercom service" in result.stdout
        
        # Wait for service to restart
        time.sleep(10)
        
        # Get Chrome PID after rename
        result_after = host.run("pgrep -f 'vdo.ninja' | head -1")
        pid_after = result_after.stdout.strip() if result_after.succeeded else None
        
        # PIDs should be different (service restarted)
        assert pid_after is not None
        assert pid_before != pid_after
        
        # Return to read-only
        host.run("ndi-bridge-ro")
    
    @pytest.mark.slow
    @pytest.mark.destructive
    def test_chrome_uses_new_name_in_vdo_url(self, host):
        """Test that Chrome uses new name in VDO.Ninja URL after rename."""
        # Make filesystem writable
        host.run("ndi-bridge-rw")
        
        # Run set-name command
        result = host.run(f"ndi-bridge-set-name {self.test_name}")
        assert result.succeeded
        
        # Wait for service to restart
        time.sleep(10)
        
        # Check Chrome command line for new name
        result = host.run("ps aux | grep -o 'chrome.*push=[^ ]*' | head -1")
        if result.succeeded and result.stdout:
            assert f"push={self.test_name}" in result.stdout
        
        # Return to read-only
        host.run("ndi-bridge-ro")
    
    def test_intercom_service_file_has_restart_policy(self, host):
        """Test that intercom service has restart policy configured."""
        service_file = host.file("/etc/systemd/system/ndi-bridge-intercom.service")
        assert service_file.exists
        assert "Restart=" in service_file.content_string
    
    def test_ndi_capture_service_is_restarted(self, host):
        """Test that NDI capture service is also restarted."""
        # This is already in the script, just verify it's there
        script = host.file("/usr/local/bin/ndi-bridge-set-name")
        assert "systemctl restart ndi-capture" in script.content_string
    
    def test_avahi_daemon_is_restarted(self, host):
        """Test that Avahi daemon is restarted for mDNS updates."""
        script = host.file("/usr/local/bin/ndi-bridge-set-name")
        assert "systemctl restart avahi-daemon" in script.content_string