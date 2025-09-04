"""
Atomic tests for Inferno ALSA plugin (Dante audio implementation).
Each test validates exactly ONE thing following the project's testing architecture.
"""
import pytest


class TestInfernoPlugin:
    """Test Inferno ALSA plugin installation and configuration."""
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_inferno_plugin_exists(self, host):
        """Test that Inferno ALSA plugin is installed."""
        assert host.file("/usr/lib/x86_64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so").exists
    
    @pytest.mark.dante
    def test_inferno_plugin_size(self, host):
        """Test that Inferno plugin has reasonable size (>1MB)."""
        plugin = host.file("/usr/lib/x86_64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so")
        assert plugin.size > 1000000  # Should be several MB
    
    @pytest.mark.dante
    def test_inferno_plugin_permissions(self, host):
        """Test that Inferno plugin has correct permissions."""
        plugin = host.file("/usr/lib/x86_64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so")
        assert plugin.mode == 0o755
    
    @pytest.mark.dante
    def test_inferno_plugin_owner(self, host):
        """Test that Inferno plugin is owned by root."""
        plugin = host.file("/usr/lib/x86_64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so")
        assert plugin.user == "root"
        assert plugin.group == "root"


class TestALSAConfiguration:
    """Test ALSA configuration for Dante."""
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_asound_conf_exists(self, host):
        """Test that ALSA system config exists."""
        assert host.file("/etc/asound.conf").exists
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_dante_pcm_device_defined(self, host):
        """Test that dante PCM device is defined."""
        config = host.file("/etc/asound.conf").content_string
        assert "pcm.dante" in config
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_dante_uses_inferno_type(self, host):
        """Test that dante device uses 'type inferno'."""
        config = host.file("/etc/asound.conf").content_string
        assert "type inferno" in config
    
    @pytest.mark.dante
    def test_dante_not_using_plug_type(self, host):
        """Test that dante device does NOT use 'type plug'."""
        config = host.file("/etc/asound.conf").content_string
        # Check the dante device section specifically
        import re
        dante_section = re.search(r'pcm\.dante\s*\{[^}]*\}', config, re.DOTALL)
        if dante_section:
            assert "type plug" not in dante_section.group()
    
    @pytest.mark.dante
    def test_dante_sample_rate_96000(self, host):
        """Test that dante is configured for 96kHz."""
        config = host.file("/etc/asound.conf").content_string
        assert "SAMPLE_RATE 96000" in config or "sample_rate 96000" in config
    
    @pytest.mark.dante
    def test_dante_stereo_channels(self, host):
        """Test that dante is configured for stereo (2 channels)."""
        config = host.file("/etc/asound.conf").content_string
        assert "RX_CHANNELS 2" in config or "rx_channels 2" in config
        assert "TX_CHANNELS 2" in config or "tx_channels 2" in config
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_dante_clock_path_configured(self, host):
        """Test that CLOCK_PATH is configured."""
        config = host.file("/etc/asound.conf").content_string
        assert "CLOCK_PATH" in config
    
    @pytest.mark.dante
    def test_dante_clock_path_correct(self, host):
        """Test that CLOCK_PATH points to correct socket."""
        config = host.file("/etc/asound.conf").content_string
        assert '"/tmp/ptp-usrvclock"' in config
    
    @pytest.mark.dante
    def test_dante_device_name_configured(self, host):
        """Test that Dante device name is configured."""
        config = host.file("/etc/asound.conf").content_string
        assert "DEVICE_NAME" in config or "device_name" in config
    
    @pytest.mark.dante
    def test_dante_interface_configured(self, host):
        """Test that Dante network interface is configured."""
        config = host.file("/etc/asound.conf").content_string
        assert 'INTERFACE "br0"' in config or 'interface "br0"' in config


class TestDanteDeviceAvailability:
    """Test Dante device availability in ALSA."""
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_dante_device_listed_by_aplay(self, host):
        """Test that dante device is listed by aplay."""
        result = host.run("aplay -L 2>/dev/null | grep '^dante$'")
        assert result.exit_code == 0
    
    @pytest.mark.dante
    def test_dante_device_can_be_opened(self, host):
        """Test that dante device can be opened for playback."""
        # Try to open the device briefly
        result = host.run("timeout 1 speaker-test -D dante -c 2 -r 96000 -F S32_LE -t sine -l 1 2>&1")
        # Should not have "cannot find device" or similar errors
        assert "cannot find device dante" not in result.stdout.lower()
        assert "unknown PCM dante" not in result.stdout.lower()
    
    @pytest.mark.dante
    def test_dante_device_accepts_96khz(self, host):
        """Test that dante device accepts 96kHz sample rate."""
        result = host.run("timeout 1 speaker-test -D dante -c 2 -r 96000 -F S32_LE -t sine -l 1 2>&1")
        assert "Rate set to 96000Hz" in result.stdout
    
    @pytest.mark.dante
    def test_dante_device_accepts_s32le_format(self, host):
        """Test that dante device accepts S32_LE format."""
        result = host.run("timeout 1 speaker-test -D dante -c 2 -r 96000 -F S32_LE -t sine -l 1 2>&1")
        assert "S32_LE" in result.stdout