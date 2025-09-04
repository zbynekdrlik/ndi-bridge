"""
Atomic tests for Dante audio bridge services.
Each test validates exactly ONE thing following the project's testing architecture.
"""
import pytest
import time


class TestDanteServices:
    """Test Dante-related services are properly installed and configured."""
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_statime_service_exists(self, host):
        """Test that statime.service file exists."""
        assert host.file("/etc/systemd/system/statime.service").exists
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_statime_service_enabled(self, host):
        """Test that statime.service is enabled."""
        assert host.service("statime").is_enabled
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_statime_service_running(self, host):
        """Test that statime.service is running."""
        assert host.service("statime").is_running
    
    @pytest.mark.dante
    def test_statime_binary_exists(self, host):
        """Test that statime binary is installed."""
        assert host.file("/usr/local/bin/statime").exists
    
    @pytest.mark.dante
    def test_statime_binary_executable(self, host):
        """Test that statime binary is executable."""
        assert host.file("/usr/local/bin/statime").mode == 0o755
    
    @pytest.mark.dante
    def test_statime_config_exists(self, host):
        """Test that statime configuration exists."""
        assert host.file("/etc/statime.toml").exists
    
    @pytest.mark.dante
    def test_statime_config_has_ptpv1(self, host):
        """Test that statime config specifies PTPv1."""
        config = host.file("/etc/statime.toml").content_string
        assert "PTPv1" in config or "ptpv1" in config
    
    @pytest.mark.dante
    def test_statime_config_has_usrvclock(self, host):
        """Test that statime config enables usrvclock export."""
        config = host.file("/etc/statime.toml").content_string
        assert "usrvclock" in config
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_dante_bridge_service_exists(self, host):
        """Test that dante-bridge.service file exists."""
        assert host.file("/etc/systemd/system/dante-bridge.service").exists
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_dante_bridge_service_enabled(self, host):
        """Test that dante-bridge.service is enabled."""
        assert host.service("dante-bridge").is_enabled
    
    @pytest.mark.dante
    def test_dante_bridge_service_running(self, host):
        """Test that dante-bridge.service is running."""
        assert host.service("dante-bridge").is_running
    
    @pytest.mark.dante
    def test_dante_bridge_script_exists(self, host):
        """Test that main dante bridge script exists."""
        assert host.file("/usr/local/bin/media-bridge-dante").exists
    
    @pytest.mark.dante
    def test_dante_bridge_pipewire_script_exists(self, host):
        """Test that PipeWire dante bridge script exists."""
        assert host.file("/usr/local/bin/media-bridge-dante-pipewire").exists
    
    @pytest.mark.dante
    def test_dante_bridge_production_script_exists(self, host):
        """Test that production dante bridge script exists."""
        assert host.file("/usr/local/bin/media-bridge-dante-production").exists
    
    @pytest.mark.dante
    def test_dante_status_script_exists(self, host):
        """Test that dante status script exists."""
        assert host.file("/usr/local/bin/media-bridge-dante-status").exists
    
    @pytest.mark.dante
    def test_dante_config_script_exists(self, host):
        """Test that dante config script exists."""
        assert host.file("/usr/local/bin/media-bridge-dante-config").exists
    
    @pytest.mark.dante
    def test_dante_logs_script_exists(self, host):
        """Test that dante logs script exists."""
        assert host.file("/usr/local/bin/media-bridge-dante-logs").exists


class TestStatiemPTPClock:
    """Test Statime PTP clock functionality."""
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_ptp_clock_socket_exists(self, host):
        """Test that PTP clock socket is created."""
        # Restart statime to ensure it's running
        host.run("systemctl restart statime 2>/dev/null || true")
        time.sleep(2)
        assert host.file("/tmp/ptp-usrvclock").exists
    
    @pytest.mark.dante
    def test_ptp_clock_socket_is_socket(self, host):
        """Test that PTP clock file is a socket."""
        file_info = host.file("/tmp/ptp-usrvclock")
        if file_info.exists:
            assert file_info.is_socket
    
    @pytest.mark.dante
    def test_statime_is_ptp_follower(self, host):
        """Test that statime is configured as PTP follower."""
        result = host.run("journalctl -u statime -n 50 --no-pager 2>/dev/null | grep -i slave")
        assert result.exit_code == 0
    
    @pytest.mark.dante
    def test_statime_not_ptp_master(self, host):
        """Test that statime is NOT configured as PTP master."""
        result = host.run("journalctl -u statime -n 50 --no-pager 2>/dev/null | grep -i 'master'")
        # Should not find "MASTER" state (may find "grandmaster" which is OK)
        assert "MASTER" not in result.stdout
    
    @pytest.mark.dante
    def test_statime_using_software_timestamping(self, host):
        """Test that statime falls back to software timestamping."""
        result = host.run("journalctl -u statime -n 50 --no-pager 2>/dev/null | grep -i 'software'")
        assert result.exit_code == 0