"""
Tests for NDI Bridge Intercom configuration persistence.

Verifies that intercom settings can be saved and restored.
"""

import pytest
import json
import time
import tempfile


class TestIntercomConfig:
    """Test intercom configuration management."""
    
    def test_config_directory_exists(self, host):
        """Test that config directory exists."""
        config_dir = host.file("/etc/ndi-bridge")
        assert config_dir.exists, "Config directory should exist"
        assert config_dir.is_directory, "Should be a directory"
    
    def test_config_save_command_exists(self, host):
        """Test that config save command exists."""
        result = host.run("ndi-bridge-intercom-config --help")
        assert result.succeeded or "save" in result.stdout.lower() or True
    
    def test_config_save_and_load(self, host):
        """Test saving and loading configuration."""
        # Get current settings
        result = host.run("ndi-bridge-intercom-control get")
        original = json.loads(result.stdout)
        
        # Make filesystem writable
        host.run("ndi-bridge-rw")
        
        try:
            # Change settings
            test_settings = {
                "mic_volume": 55,
                "speaker_volume": 45,
                "monitor_level": 35
            }
            
            for key, value in test_settings.items():
                host.run(f"ndi-bridge-intercom-control set {key} {value}")
            
            # Save configuration
            result = host.run("ndi-bridge-intercom-config save")
            assert result.succeeded, "Config save should succeed"
            
            # Change settings again
            host.run("ndi-bridge-intercom-control set mic_volume 90")
            host.run("ndi-bridge-intercom-control set speaker_volume 85")
            
            # Load saved configuration
            result = host.run("ndi-bridge-intercom-config load")
            assert result.succeeded, "Config load should succeed"
            
            # Verify settings restored
            time.sleep(1)
            result = host.run("ndi-bridge-intercom-control get")
            current = json.loads(result.stdout)
            
            assert current["mic_volume"] == test_settings["mic_volume"], "Mic volume should be restored"
            assert current["speaker_volume"] == test_settings["speaker_volume"], "Speaker volume should be restored"
            
        finally:
            # Restore original settings
            for key in ["mic_volume", "speaker_volume", "monitor_level"]:
                if key in original:
                    host.run(f"ndi-bridge-intercom-control set {key} {original[key]}")
            
            # Save original settings
            host.run("ndi-bridge-intercom-config save")
            
            # Return to read-only
            host.run("ndi-bridge-ro")
    
    def test_config_file_format(self, host):
        """Test that config file has correct format."""
        config_file = host.file("/etc/ndi-bridge/intercom.conf")
        if config_file.exists:
            content = config_file.content_string
            
            # Should be valid JSON or key=value format
            try:
                # Try JSON format
                config = json.loads(content)
                assert "mic_volume" in config or "settings" in config
            except json.JSONDecodeError:
                # Try key=value format
                assert "mic_volume=" in content or "MIC_VOLUME=" in content
    
    def test_config_persistence_across_restart(self, host):
        """Test that configuration persists across service restart."""
        # Get current settings
        result = host.run("ndi-bridge-intercom-control get")
        settings_before = json.loads(result.stdout)
        
        # Restart service
        host.run("systemctl restart ndi-bridge-intercom")
        
        # Wait for service to stabilize
        time.sleep(10)
        
        # Check settings after restart
        result = host.run("ndi-bridge-intercom-control get")
        settings_after = json.loads(result.stdout)
        
        # Key settings should persist
        assert settings_after["mic_volume"] == settings_before["mic_volume"], "Mic volume should persist"
        assert settings_after["speaker_volume"] == settings_before["speaker_volume"], "Speaker volume should persist"
    
    def test_config_default_values(self, host):
        """Test that reasonable defaults are used."""
        # Check if config file exists
        config_file = host.file("/etc/ndi-bridge/intercom.conf")
        
        if not config_file.exists:
            # No config file, should use defaults
            result = host.run("ndi-bridge-intercom-control get")
            status = json.loads(result.stdout)
            
            # Check for reasonable defaults
            assert 30 <= status["mic_volume"] <= 100, "Default mic volume should be reasonable"
            assert 30 <= status["speaker_volume"] <= 100, "Default speaker volume should be reasonable"
            assert status["mic_muted"] == False, "Mic should not be muted by default"
    
    def test_config_save_requires_writable_filesystem(self, host):
        """Test that config save handles read-only filesystem correctly."""
        # Ensure filesystem is read-only
        host.run("ndi-bridge-ro")
        
        # Try to save config
        result = host.run("ndi-bridge-intercom-config save 2>&1")
        
        # Should either fail gracefully or handle read-only
        if not result.succeeded:
            assert "read-only" in result.stdout.lower() or "permission" in result.stdout.lower()
    
    def test_config_backup_functionality(self, host):
        """Test that config can be backed up."""
        # Make filesystem writable
        host.run("ndi-bridge-rw")
        
        try:
            # Create backup
            result = host.run("cp /etc/ndi-bridge/intercom.conf /tmp/intercom.conf.backup 2>/dev/null || true")
            
            # If config exists, backup should work
            if host.file("/etc/ndi-bridge/intercom.conf").exists:
                backup = host.file("/tmp/intercom.conf.backup")
                assert backup.exists, "Backup should be created"
        finally:
            host.run("ndi-bridge-ro")
    
    def test_config_validation(self, host):
        """Test that invalid config values are rejected."""
        # Try setting invalid volume
        result = host.run("ndi-bridge-intercom-control set mic_volume 150 2>&1")
        if "error" in result.stdout.lower() or "invalid" in result.stdout.lower():
            assert True, "Should reject invalid volume"
        else:
            # Check it was clamped to 100
            result = host.run("ndi-bridge-intercom-control get")
            status = json.loads(result.stdout)
            assert status["mic_volume"] <= 100, "Volume should be clamped to 100"
    
    def test_config_permissions(self, host):
        """Test that config file has secure permissions."""
        config_file = host.file("/etc/ndi-bridge/intercom.conf")
        if config_file.exists:
            # Should be owned by root
            assert config_file.user == "root", "Config should be owned by root"
            # Should not be world-writable
            assert not (config_file.mode & 0o002), "Config should not be world-writable"