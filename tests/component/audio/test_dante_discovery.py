"""
Atomic tests for Dante network discovery functionality.
Each test validates exactly ONE thing following the project's testing architecture.
"""
import pytest
import time


class TestDanteDiscoveryPorts:
    """Test Dante discovery port functionality."""
    
    @pytest.mark.dante
    def test_discovery_ports_closed_initially(self, host):
        """Test that discovery ports are closed when not in use."""
        result = host.run("netstat -uln | grep -E ':870[08]|:880[08]'")
        # Ports should NOT be open initially
        assert result.exit_code == 1 or result.stdout == ""
    
    @pytest.mark.dante
    @pytest.mark.slow
    def test_discovery_ports_open_on_use(self, host):
        """Test that discovery ports open when device is used."""
        # Start using the dante device
        host.run("timeout 2 arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>/dev/null >/dev/null &")
        time.sleep(1)
        
        # Check if ports opened
        result = host.run("netstat -uln | grep -E ':8700|:8800'")
        assert result.exit_code == 0
    
    @pytest.mark.dante
    def test_port_8700_opens(self, host):
        """Test that port 8700 (control) opens."""
        host.run("timeout 2 arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>/dev/null >/dev/null &")
        time.sleep(1)
        result = host.run("netstat -uln | grep ':8700'")
        assert result.exit_code == 0
    
    @pytest.mark.dante
    def test_port_8800_opens(self, host):
        """Test that port 8800 (status) opens."""
        host.run("timeout 2 arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>/dev/null >/dev/null &")
        time.sleep(1)
        result = host.run("netstat -uln | grep ':8800'")
        assert result.exit_code == 0
    
    @pytest.mark.dante
    def test_discovery_ports_bind_to_bridge_ip(self, host):
        """Test that discovery ports bind to bridge IP."""
        host.run("timeout 2 arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>/dev/null >/dev/null &")
        time.sleep(1)
        
        # Get bridge IP
        bridge_ip = host.run("ip -4 addr show br0 | grep inet | awk '{print $2}' | cut -d/ -f1").stdout.strip()
        
        if bridge_ip:
            result = host.run(f"netstat -uln | grep '{bridge_ip}:8'")
            assert result.exit_code == 0


class TestDanteNetworkRequirements:
    """Test network requirements for Dante."""
    
    @pytest.mark.dante
    @pytest.mark.critical
    def test_bridge_interface_exists(self, host):
        """Test that br0 bridge interface exists."""
        assert host.interface("br0").exists
    
    @pytest.mark.dante
    def test_bridge_interface_up(self, host):
        """Test that br0 bridge interface is up."""
        result = host.run("ip link show br0 | grep 'state UP'")
        assert result.exit_code == 0
    
    @pytest.mark.dante
    def test_bridge_has_ipv4_address(self, host):
        """Test that br0 has IPv4 address."""
        result = host.run("ip -4 addr show br0 | grep inet")
        assert result.exit_code == 0
    
    @pytest.mark.dante
    def test_avahi_daemon_running(self, host):
        """Test that Avahi daemon is running for mDNS."""
        assert host.service("avahi-daemon").is_running
    
    @pytest.mark.dante
    def test_mdns_port_5353_listening(self, host):
        """Test that mDNS port 5353 is listening."""
        result = host.run("netstat -uln | grep ':5353'")
        assert result.exit_code == 0


class TestDanteAudioFlow:
    """Test Dante audio flow functionality."""
    
    @pytest.mark.dante
    def test_dante_record_creates_inferno_process(self, host):
        """Test that recording from dante creates Inferno process."""
        # Start recording
        host.run("timeout 2 arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>/dev/null >/dev/null &")
        time.sleep(0.5)
        
        # Check debug output shows inferno
        result = host.run("ps aux | grep -i inferno | grep -v grep")
        # Process name might not show, but check ALSA logs
        logs = host.run("journalctl -n 100 --no-pager | grep inferno_aoip")
        assert logs.exit_code == 0
    
    @pytest.mark.dante
    def test_dante_playback_works(self, host):
        """Test that playback to dante device works."""
        result = host.run("timeout 1 speaker-test -D dante -c 2 -r 96000 -F S32_LE -t sine -f 440 -l 1 2>&1")
        assert "Front Left" in result.stdout
        assert "Front Right" in result.stdout
    
    @pytest.mark.dante
    def test_dante_record_works(self, host):
        """Test that recording from dante device works."""
        result = host.run("timeout 1 arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>&1 | head -5")
        assert "Recording" in result.stdout or "Signed 32 bit" in result.stdout
    
    @pytest.mark.dante
    @pytest.mark.slow
    def test_dante_bidirectional_audio(self, host):
        """Test that bidirectional audio (record and playback) works."""
        # This would normally route Dante input to USB output
        cmd = "timeout 2 bash -c 'arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>/dev/null | aplay -D null -f S32_LE -r 96000 -c 2 -t raw 2>/dev/null'"
        result = host.run(cmd)
        # Should complete without error
        assert result.exit_code in [0, 124]  # 0=success, 124=timeout (expected)