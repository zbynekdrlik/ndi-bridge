"""
Integration tests for complete Dante audio bridge functionality.
Tests multi-component interactions following the project's testing architecture.
"""
import pytest
import time


class TestDanteFullStack:
    """Test the complete Dante audio bridge stack integration."""
    
    @pytest.mark.dante
    @pytest.mark.integration
    @pytest.mark.slow
    def test_dante_stack_startup_sequence(self, host):
        """Test that Dante stack starts up in correct sequence."""
        # Restart services in correct order
        host.run("systemctl restart statime")
        time.sleep(2)
        
        # Check statime started and created clock
        assert host.service("statime").is_running
        assert host.file("/tmp/ptp-usrvclock").exists
        
        # Restart dante bridge
        host.run("systemctl restart dante-bridge")
        time.sleep(2)
        
        # Check dante bridge started
        assert host.service("dante-bridge").is_running
    
    @pytest.mark.dante
    @pytest.mark.integration
    def test_dante_with_usb_audio_detection(self, host):
        """Test that Dante bridge detects USB audio devices."""
        # Check if USB audio exists
        result = host.run("aplay -l | grep -i usb")
        if result.exit_code == 0:
            # USB audio found, check if dante bridge uses it
            logs = host.run("journalctl -u dante-bridge -n 50 --no-pager | grep -i 'usb\\|audio'")
            assert logs.exit_code == 0
    
    @pytest.mark.dante
    @pytest.mark.integration
    @pytest.mark.slow
    def test_dante_discovery_with_active_stream(self, host):
        """Test that Dante becomes discoverable during active streaming."""
        # Start a stream
        host.run("timeout 3 arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>/dev/null >/dev/null &")
        time.sleep(1)
        
        # Check discovery ports
        ports_result = host.run("netstat -uln | grep -E ':870[08]|:880[08]'")
        assert ports_result.exit_status == 0
        
        # Check at least 2 ports opened (8700, 8800 minimum)
        port_count = len(ports_result.stdout.strip().split('\n'))
        assert port_count >= 2
    
    @pytest.mark.dante
    @pytest.mark.integration
    def test_dante_clock_synchronization(self, host):
        """Test that Dante uses PTP clock synchronization."""
        # Check statime is providing clock
        assert host.file("/tmp/ptp-usrvclock").exists
        
        # Start audio stream
        host.run("timeout 2 speaker-test -D dante -c 2 -r 96000 -F S32_LE -t sine -l 1 2>&1 &")
        time.sleep(1)
        
        # Check that inferno connected to clock
        logs = host.run("journalctl -n 100 --no-pager | grep -E 'clock ready|clock_receiver updated'")
        assert logs.exit_code == 0
    
    @pytest.mark.dante
    @pytest.mark.integration
    @pytest.mark.performance
    def test_dante_audio_latency(self, host):
        """Test that Dante audio has acceptable latency."""
        # This is a placeholder for latency testing
        # Real latency testing would require audio analysis
        result = host.run("timeout 1 speaker-test -D dante -c 2 -r 96000 -F S32_LE -b 256 -p 64 2>&1")
        # Check that small buffer sizes are accepted
        assert "Buffer" in result.stdout
    
    @pytest.mark.dante
    @pytest.mark.integration
    def test_dante_96khz_operation(self, host):
        """Test that Dante operates at required 96kHz."""
        result = host.run("timeout 1 speaker-test -D dante -c 2 -r 96000 -F S32_LE -t sine -l 1 2>&1")
        assert "Rate set to 96000Hz" in result.stdout
        
        # Try wrong sample rate - should fail or be resampled
        result_48k = host.run("timeout 1 speaker-test -D dante -c 2 -r 48000 -F S32_LE -t sine -l 1 2>&1")
        # Either fails or gets resampled to 96k
        assert "96000" in result_48k.stdout or "Invalid" in result_48k.stdout
    
    @pytest.mark.dante
    @pytest.mark.integration
    def test_dante_with_pipewire(self, host):
        """Test Dante integration with PipeWire when available."""
        if host.service("pipewire").is_enabled:
            # PipeWire should be running for resampling
            host.run("systemctl start pipewire 2>/dev/null || true")
            time.sleep(1)
            
            # Check if PipeWire version of dante bridge is used
            link_target = host.run("readlink /usr/local/bin/media-bridge-dante").stdout.strip()
            assert "pipewire" in link_target.lower()
    
    @pytest.mark.dante  
    @pytest.mark.integration
    def test_dante_error_recovery(self, host):
        """Test that Dante recovers from errors."""
        # Kill dante bridge
        host.run("systemctl stop dante-bridge")
        time.sleep(1)
        
        # Should be stopped
        assert not host.service("dante-bridge").is_running
        
        # Restart
        host.run("systemctl start dante-bridge")
        time.sleep(2)
        
        # Should be running again
        assert host.service("dante-bridge").is_running
        
        # Test audio still works
        result = host.run("timeout 1 arecord -D dante -f S32_LE -r 96000 -c 2 -t raw 2>&1 | head -5")
        assert "Recording" in result.stdout or "Signed 32 bit" in result.stdout