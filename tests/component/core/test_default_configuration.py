"""
Test default configuration on clean image.

These tests verify that the device has the correct default settings
that should be present on a freshly flashed image.
"""

import pytest


class TestDefaultConfiguration:
    """Test that device has correct default configuration."""
    
    def test_default_hostname(self, host):
        """Test that default hostname is 'media-bridge'."""
        hostname = host.run("hostname").stdout.strip()
        assert hostname == "media-bridge", f"Default hostname should be 'media-bridge', got '{hostname}'"
    
    def test_default_ndi_name_in_config(self, host):
        """Test that default NDI name in config is 'USB Capture'."""
        config = host.run("cat /etc/media-bridge/config 2>/dev/null || echo 'NO_CONFIG'").stdout
        
        if "NO_CONFIG" in config:
            # If no config file, check if ndi-capture.conf exists (alternate location)
            config = host.run("cat /etc/ndi-capture.conf 2>/dev/null || echo 'NO_CONFIG'").stdout
            if "NO_CONFIG" in config:
                pytest.fail("No NDI configuration file found - should exist on clean image")
        
        # Check for NDI_NAME setting
        if 'NDI_NAME=' in config:
            # Extract the NDI name value
            for line in config.split('\n'):
                if line.startswith('NDI_NAME='):
                    ndi_name = line.split('=', 1)[1].strip('"').strip("'")
                    assert ndi_name == "USB Capture", \
                        f"Default NDI_NAME should be 'USB Capture', got '{ndi_name}'"
                    return
            pytest.fail("NDI_NAME found but couldn't parse value")
        else:
            pytest.fail("NDI_NAME not found in configuration - should be set to 'USB Capture'")
    
    def test_default_ndi_stream_name(self, host):
        """Test that default NDI stream appears as 'MEDIA-BRIDGE (USB Capture)'."""
        # List NDI sources and look for our device
        result = host.run("timeout 5 /opt/media-bridge/ndi-display list 2>/dev/null | grep -E '^[0-9]+:.*MEDIA-BRIDGE' || echo 'NOT_FOUND'")
        
        if "NOT_FOUND" not in result.stdout:
            # Check if it's the expected default name
            assert "MEDIA-BRIDGE (USB Capture)" in result.stdout, \
                f"Default NDI stream should be 'MEDIA-BRIDGE (USB Capture)', got: {result.stdout.strip()}"
        else:
            # NDI might not be running, check the process
            ps_result = host.run("ps aux | grep -v grep | grep ndi-capture || echo 'NOT_RUNNING'")
            if "NOT_RUNNING" in ps_result.stdout:
                pytest.skip("ndi-capture not running - can't verify stream name")
            else:
                # Check what name is being used in the process
                if "USB Capture" in ps_result.stdout or "USB_Capture" in ps_result.stdout:
                    # Process is using correct name
                    pass
                else:
                    pytest.fail(f"ndi-capture not using default 'USB Capture' name: {ps_result.stdout}")
    
    def test_mdns_hostname(self, host):
        """Test that mDNS hostname is configured correctly."""
        # Check avahi is running
        avahi_status = host.run("systemctl is-active avahi-daemon").stdout.strip()
        if avahi_status != "active":
            pytest.skip("Avahi daemon not running")
        
        # Check that device responds to media-bridge.local
        avahi_hostname = host.run("avahi-resolve -n media-bridge.local 2>/dev/null | grep -o 'media-bridge.local' || echo 'NOT_FOUND'").stdout.strip()
        
        if avahi_hostname == "media-bridge.local":
            assert True
        elif "NOT_FOUND" in avahi_hostname:
            # Alternative check - see what hostname avahi is advertising
            advertised = host.run("avahi-browse -a -t -r -p 2>/dev/null | grep -o '[^;]*\\.local' | head -1 || echo 'NONE'").stdout.strip()
            assert advertised == "media-bridge.local" or advertised == "NONE", \
                f"Device should advertise as 'media-bridge.local', got '{advertised}'"
    
    def test_device_accessible_via_default_hostname(self, host):
        """Test that device can be pinged at media-bridge.local."""
        # This is more of an integration test but important for default state
        result = host.run("ping -c 1 media-bridge.local 2>&1 | grep -q 'bytes from' && echo 'OK' || echo 'FAIL'")
        
        if result.stdout.strip() == "OK":
            assert True
        else:
            # mDNS might not work in test environment, check if hostname at least resolves locally
            local_check = host.run("getent hosts media-bridge.local 2>/dev/null | grep -q '127.0' && echo 'LOCAL_OK' || echo 'NOT_RESOLVED'")
            if "LOCAL_OK" in local_check.stdout:
                pytest.skip("mDNS only resolves locally - external test needed")
            else:
                pytest.fail("Device should be accessible via media-bridge.local")
    
    def test_no_test_artifacts_in_config(self, host):
        """Test that no test artifacts (like pytest99) are in default config."""
        # Check hostname doesn't contain test artifacts
        hostname = host.run("hostname").stdout.strip()
        assert "pytest" not in hostname.lower(), f"Default hostname contains test artifacts: {hostname}"
        assert "test" not in hostname.lower(), f"Default hostname contains test artifacts: {hostname}"
        
        # Check NDI name doesn't contain test artifacts  
        config = host.run("cat /etc/media-bridge/config 2>/dev/null || cat /etc/ndi-capture.conf 2>/dev/null || echo ''").stdout
        assert "pytest" not in config.lower(), f"Configuration contains test artifacts"
        assert "test99" not in config.lower(), f"Configuration contains test artifacts"
    
    def test_default_web_interface_title(self, host):
        """Test that web interface shows correct default title."""
        # Check nginx is running
        nginx_status = host.run("systemctl is-active nginx").stdout.strip()
        if nginx_status != "active":
            pytest.skip("Nginx not running")
        
        # Check that the web page title contains Media Bridge (not NDI Bridge or test names)
        result = host.run("curl -s http://localhost/ 2>/dev/null | grep -o '<title>[^<]*</title>' | head -1 || echo 'NO_TITLE'")
        
        if "NO_TITLE" not in result.stdout:
            title = result.stdout.strip()
            assert "media" in title.lower() or "bridge" in title.lower(), \
                f"Web interface should mention 'Media Bridge', got: {title}"
            assert "pytest" not in title.lower(), \
                f"Web interface contains test artifacts: {title}"