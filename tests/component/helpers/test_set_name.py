"""Tests for media-bridge-set-name script functionality."""

import pytest
import time

class TestSetNameScript:
    """Test media-bridge-set-name helper script."""
    
    def test_set_name_with_underscores(self, host):
        """Test that set-name properly sanitizes underscores in hostnames."""
        # Set a name with underscores
        result = host.run("media-bridge-set-name test_name_123")
        assert result.exit_status == 0
        
        # Wait for services to restart
        time.sleep(3)
        
        # Check that hostname has hyphens instead of underscores
        hostname = host.run("hostname").stdout.strip()
        assert hostname == "media-bridge-test-name-123", \
            f"Hostname should convert underscores to hyphens, got: {hostname}"
        
        # Check that NDI name keeps underscores
        ndi_name = host.run("grep NDI_NAME /etc/media-bridge/config").stdout.strip()
        assert 'NDI_NAME="test_name_123"' in ndi_name, \
            f"NDI name should keep underscores, got: {ndi_name}"
        
        # Check Avahi config has sanitized hostname
        avahi_hostname = host.run("grep '^host-name=' /etc/avahi/avahi-daemon.conf").stdout.strip()
        assert "host-name=media-bridge-test-name-123" in avahi_hostname, \
            f"Avahi hostname should not have underscores, got: {avahi_hostname}"
        
        # Check /etc/hosts
        hosts_entry = host.run("grep 127.0.1.1 /etc/hosts").stdout.strip()
        assert "media-bridge-test-name-123" in hosts_entry, \
            f"/etc/hosts should have sanitized hostname, got: {hosts_entry}"
        assert "test-name-123" in hosts_entry, \
            f"/etc/hosts should have short alias, got: {hosts_entry}"
    
    def test_set_name_simple(self, host):
        """Test setting a simple name without special characters."""
        result = host.run("media-bridge-set-name cam1")
        assert result.exit_status == 0
        
        time.sleep(3)
        
        # Verify all components updated correctly
        hostname = host.run("hostname").stdout.strip()
        assert hostname == "media-bridge-cam1"
        
        ndi_name = host.run("grep NDI_NAME /etc/media-bridge/config").stdout.strip()
        assert 'NDI_NAME="cam1"' in ndi_name
        
        avahi_hostname = host.run("grep '^host-name=' /etc/avahi/avahi-daemon.conf").stdout.strip()
        assert "host-name=media-bridge-cam1" in avahi_hostname
    
    def test_avahi_alias_service(self, host):
        """Test that avahi-alias service is created and running."""
        # Set a name to trigger alias creation
        host.run("media-bridge-set-name testdevice")
        time.sleep(3)
        
        # Check that avahi-alias service exists and is running
        service_status = host.run("systemctl is-active avahi-alias").stdout.strip()
        assert service_status == "active", \
            f"avahi-alias service should be active, got: {service_status}"
        
        # Check that the service is enabled
        enabled_status = host.run("systemctl is-enabled avahi-alias").stdout.strip()
        assert enabled_status == "enabled", \
            f"avahi-alias service should be enabled, got: {enabled_status}"
        
        # Check that media-bridge-publish-alias script exists
        script_exists = host.run("test -x /usr/local/bin/media-bridge-publish-alias && echo 'exists'").stdout.strip()
        assert script_exists == "exists", \
            "media-bridge-publish-alias script should exist and be executable"
    
    def test_dynamic_ip_discovery(self, host):
        """Test that avahi-alias uses dynamic IP discovery."""
        # Check the systemd service uses the wrapper script
        service_content = host.run("grep ExecStart /etc/systemd/system/avahi-alias.service").stdout.strip()
        assert "/usr/local/bin/media-bridge-publish-alias" in service_content, \
            "avahi-alias service should use dynamic IP discovery wrapper"
        
        # The service should NOT have a hardcoded IP
        assert "10.77" not in service_content and "192.168" not in service_content, \
            "avahi-alias service should not contain hardcoded IP addresses"
    
    def test_set_name_uppercase(self, host):
        """Test that uppercase names are converted to lowercase."""
        result = host.run("media-bridge-set-name CAM_UPPER")
        assert result.exit_status == 0
        
        time.sleep(3)
        
        # Check hostname is lowercase with hyphens
        hostname = host.run("hostname").stdout.strip()
        assert hostname == "media-bridge-cam-upper", \
            f"Hostname should be lowercase with hyphens, got: {hostname}"
        
        # NDI name should also be lowercase
        ndi_name = host.run("grep NDI_NAME /etc/media-bridge/config").stdout.strip()
        assert 'NDI_NAME="cam_upper"' in ndi_name, \
            f"NDI name should be lowercase, got: {ndi_name}"
    
    def test_mdns_resolution_after_rename(self, host):
        """Test that mDNS resolution works after renaming."""
        # Set a clean name
        host.run("media-bridge-set-name mdnstest")
        time.sleep(5)  # Give mDNS time to propagate
        
        # Check that we can resolve our own hostname
        resolution = host.run("avahi-resolve -n media-bridge-mdnstest.local 2>/dev/null | grep -c 'media-bridge-mdnstest.local'").stdout.strip()
        assert resolution == "1", \
            "Device should be able to resolve its own mDNS hostname"
        
        # Check that short alias is published
        alias_check = host.run("systemctl status avahi-alias | grep 'mdnstest.local'").exit_status
        assert alias_check == 0, \
            "Short alias should be published by avahi-alias service"
    
    def test_restore_default_name(self, host):
        """Test restoring to default media-bridge name."""
        # First rename to something else
        host.run("media-bridge-set-name testname")
        time.sleep(3)
        
        # Now try to restore to default (this should work with a special command or by removing config)
        # Since there's no built-in restore, we'll manually set it
        host.run("echo 'media-bridge' > /etc/hostname")
        host.run("sed -i 's/127.0.1.1.*/127.0.1.1 media-bridge/' /etc/hosts")
        host.run("sed -i 's/^host-name=.*/host-name=media-bridge/' /etc/avahi/avahi-daemon.conf")
        host.run("sed -i 's/NDI_NAME=.*/NDI_NAME=\"USB Capture\"/' /etc/media-bridge/config")
        host.run("hostname media-bridge")
        host.run("systemctl restart avahi-daemon")
        host.run("systemctl stop avahi-alias 2>/dev/null || true")
        host.run("systemctl disable avahi-alias 2>/dev/null || true")
        
        time.sleep(3)
        
        # Verify default state restored
        hostname = host.run("hostname").stdout.strip()
        assert hostname == "media-bridge", \
            f"Hostname should be restored to media-bridge, got: {hostname}"
        
        ndi_name = host.run("grep NDI_NAME /etc/media-bridge/config").stdout.strip()
        assert 'NDI_NAME="USB Capture"' in ndi_name, \
            f"NDI name should be restored to default, got: {ndi_name}"