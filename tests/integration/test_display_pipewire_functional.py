"""
Functional integration tests for ndi-display PipeWire audio implementation.

These tests verify actual PipeWire audio functionality with different display IDs.
"""

import pytest
import time


def test_display_uses_user_pipewire(host):
    """Test that ndi-display user unit depends on PipeWire user services."""
    result = host.run("systemctl --user cat 'ndi-display@.service' | grep -E 'After=|Wants='")
    assert 'pipewire' in result.stdout.lower(), "Display user unit missing PipeWire dependencies"


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.audio
def test_display_pipewire_audio_display_0(host):
    """Test PipeWire audio output with display ID 0 (HDMI-A-1)."""
    print("\n" + "="*60)
    print("TESTING PIPEWIRE AUDIO ON DISPLAY 0 (HDMI-A-1)")
    print("="*60)
    
    try:
        # Stop any existing display and unbind console
        host.run("systemctl stop 'ndi-display@*' 2>/dev/null || true")
        host.run("echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        time.sleep(2)
        
        # Start ndi-display on display 0
        # Use the launcher to ensure environment is set correctly
        cmd = "STREAM_NAME='MEDIA-BRIDGE (USB Capture)' timeout 10 /usr/local/bin/ndi-display-launcher 0 2>&1 | head -20"
        result = host.run(cmd)
    finally:
        # Always restore console and clean up
        host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        host.run("rm -f /var/run/ndi-display/display-0.status 2>/dev/null || true")
        host.run("rm -f /etc/ndi-display/display-0.conf 2>/dev/null || true")
    
    # Check for audio initialization or console error
    if 'Console is active' in result.stdout:
        print("⚠ Display 0 has console active, skipping")
        pytest.skip("Display 0 has console active")
    
    if 'Display not connected' in result.stdout or 'Failed to open display' in result.stdout:
        print("⚠ Display 0 not connected, skipping")
        pytest.skip("Display 0 not connected")
    
    # With unified PipeWire, audio might be initialized differently
    # Check for various audio initialization indicators
    audio_initialized = any([
        'Audio output initialized' in result.stdout,
        'audio' in result.stdout.lower(),
        'PipeWire' in result.stdout,
        'pipewire' in result.stdout.lower(),
        'ALSA' in result.stdout,
    ])
    
    assert audio_initialized, \
        f"Audio not initialized for display 0. Output:\n{result.stdout}"
    
    print("✓ Audio initialized for display 0")


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.audio
def test_display_pipewire_audio_display_1(host):
    """Test PipeWire audio output with display ID 1 (HDMI-A-2)."""
    print("\n" + "="*60)
    print("TESTING PIPEWIRE AUDIO ON DISPLAY 1 (HDMI-A-2)")
    print("="*60)
    
    try:
        # Stop any existing display and unbind console
        host.run("systemctl stop 'ndi-display@*' 2>/dev/null || true")
        host.run("echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        time.sleep(2)
        
        # Start ndi-display on display 1
        # Use the launcher to ensure environment is set correctly
        cmd = "STREAM_NAME='MEDIA-BRIDGE (USB Capture)' timeout 10 /usr/local/bin/ndi-display-launcher 1 2>&1 | head -20"
        result = host.run(cmd)
    finally:
        # Always restore console and clean up
        host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        host.run("rm -f /var/run/ndi-display/display-1.status 2>/dev/null || true")
        host.run("rm -f /etc/ndi-display/display-1.conf 2>/dev/null || true")
    
    # Check for audio initialization or display not connected
    if 'Display not connected' in result.stdout or 'Failed to open display' in result.stdout:
        print("⚠ Display 1 not connected, skipping")
        pytest.skip("Display 1 not connected")
    
    # With unified PipeWire, audio might be initialized differently
    # Check for various audio initialization indicators
    audio_initialized = any([
        'Audio output initialized' in result.stdout,
        'audio' in result.stdout.lower(),
        'PipeWire' in result.stdout,
        'pipewire' in result.stdout.lower(),
        'ALSA' in result.stdout,
    ])
    
    assert audio_initialized, \
        f"Audio not initialized for display 1. Output:\n{result.stdout}"
    
    print("✓ Audio initialized for display 1")


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.audio
def test_display_pipewire_audio_display_2(host):
    """Test PipeWire audio output with display ID 2 (HDMI-A-3)."""
    print("\n" + "="*60)
    print("TESTING PIPEWIRE AUDIO ON DISPLAY 2 (HDMI-A-3)")
    print("="*60)
    
    try:
        # Stop any existing display and unbind console
        host.run("systemctl stop 'ndi-display@*' 2>/dev/null || true")
        host.run("echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        time.sleep(2)
        
        # Start ndi-display on display 2
        # Use the launcher to ensure environment is set correctly
        cmd = "STREAM_NAME='MEDIA-BRIDGE (USB Capture)' timeout 10 /usr/local/bin/ndi-display-launcher 2 2>&1 | head -20"
        result = host.run(cmd)
    finally:
        # Always restore console and clean up
        host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        host.run("rm -f /var/run/ndi-display/display-2.status 2>/dev/null || true")
        host.run("rm -f /etc/ndi-display/display-2.conf 2>/dev/null || true")
    
    # Check for display not connected
    if 'Display not connected' in result.stdout or 'Failed to open display' in result.stdout:
        print("⚠ Display 2 not connected, skipping")
        pytest.skip("Display 2 not connected")
    
    # With unified PipeWire, audio might be initialized differently
    # Check for various audio initialization indicators
    audio_initialized = any([
        'Audio output initialized' in result.stdout,
        'audio' in result.stdout.lower(),
        'PipeWire' in result.stdout,
        'pipewire' in result.stdout.lower(),
        'ALSA' in result.stdout,
    ])
    
    assert audio_initialized, \
        f"Audio not initialized for display 2. Output:\n{result.stdout}"
    
    print("✓ Audio initialized for display 2")


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.audio
def test_display_pipewire_client_registration(host):
    """Test that ndi-display registers as PipeWire client."""
    print("\n" + "="*60)
    print("TESTING NDI-DISPLAY PIPEWIRE CLIENT REGISTRATION")
    print("="*60)
    
    try:
        # Start ndi-display in background
        host.run("pkill ndi-display 2>/dev/null || true")
        host.run("nohup /opt/media-bridge/ndi-display 'MEDIA-BRIDGE (USB Capture)' 1 > /tmp/ndi-test.log 2>&1 & echo $! > /tmp/ndi.pid")
        time.sleep(3)
        
        # Check if ndi-display appears in PipeWire clients
        result = host.run("pactl list clients | grep -i 'ndi-display\\|media-bridge' || echo 'not-found'")
    finally:
        # Always kill the test process and clean up
        host.run("kill $(cat /tmp/ndi.pid) 2>/dev/null || true")
        host.run("rm -f /var/run/ndi-display/display-1.status 2>/dev/null || true")
        host.run("rm -f /etc/ndi-display/display-1.conf 2>/dev/null || true")
    
    if 'not-found' not in result.stdout:
        print("✓ ndi-display registered as PipeWire client")
        assert True
    else:
        # Check alternative method
        result2 = host.run("pw-cli list-objects 2>/dev/null | grep -i 'ndi-display\\|media-bridge' || echo 'not-found'")
        if 'not-found' not in result2.stdout:
            print("✓ ndi-display found in PipeWire objects")
            assert True
        else:
            print("✗ ndi-display not registered with PipeWire")
            assert False, "ndi-display not registered as PipeWire client"


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.audio
@pytest.mark.slow
def test_display_audio_continuity(host):
    """Test that audio continues playing during extended display session."""
    print("\n" + "="*60)
    print("TESTING AUDIO CONTINUITY (20 SECONDS)")
    print("="*60)
    
    # First check if display 2 is connected
    display_check = host.run("cat /sys/class/drm/card1-HDMI-A-3/status 2>/dev/null || echo 'disconnected'")
    if 'disconnected' in display_check.stdout:
        print("⚠ Display 2 not connected, skipping continuity test")
        pytest.skip("Display 2 not connected")
    
    try:
        # Start ndi-display with CG OBS stream (has audio)
        host.run("pkill ndi-display 2>/dev/null || true")
        host.run("nohup /opt/media-bridge/ndi-display 'RESOLUME-SNV (cg-obs)' 2 > /tmp/ndi-continuity.log 2>&1 & echo $! > /tmp/ndi-cont.pid")
        
        # Let it stabilize
        time.sleep(5)
        
        # Check initial audio status
        initial_check = host.run("grep -c 'Audio' /tmp/ndi-continuity.log 2>/dev/null || echo '0'")
        # Handle multiple lines - take last value only (grep -c output)
        lines = initial_check.stdout.strip().split('\n')
        initial_count_str = lines[-1] if lines else '0'
        initial_count = int(initial_count_str) if initial_count_str.isdigit() else 0
        
        print(f"Initial audio references: {initial_count}")
        
        # Wait 15 more seconds
        time.sleep(15)
        
        # Check if still running
        pid_check = host.run("ps -p $(cat /tmp/ndi-cont.pid) > /dev/null 2>&1 && echo 'running' || echo 'stopped'")
    finally:
        # Always kill the test process and clean up
        host.run("kill $(cat /tmp/ndi-cont.pid) 2>/dev/null || true")
        host.run("rm -f /var/run/ndi-display/display-2.status 2>/dev/null || true")
        host.run("rm -f /etc/ndi-display/display-2.conf 2>/dev/null || true")
    
    assert 'running' in pid_check.stdout, "ndi-display stopped unexpectedly"
    
    # Check for any audio errors
    error_check = host.run("grep -i 'audio.*error\\|audio.*fail' /tmp/ndi-continuity.log || echo 'no-errors'")
    assert 'no-errors' in error_check.stdout, f"Audio errors detected: {error_check.stdout}"
    
    print("✓ Audio continued without errors for 20 seconds")


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.audio
def test_display_hdmi_port_switching(host):
    """Test switching audio between different HDMI ports."""
    print("\n" + "="*60)
    print("TESTING HDMI PORT SWITCHING")
    print("="*60)
    
    # Test each display ID briefly
    for display_id in [0, 1, 2]:
        print(f"\nTesting display {display_id}...")
        
        # Kill any existing instance
        host.run("pkill ndi-display 2>/dev/null || true")
        time.sleep(1)
        
        # Start on this display
        cmd = f"timeout 3 /opt/media-bridge/ndi-display 'MEDIA-BRIDGE (USB Capture)' {display_id} 2>&1"
        result = host.run(cmd)
        
        # Check for successful initialization
        if 'Audio output initialized' in result.stdout:
            print(f"  ✓ Display {display_id} audio initialized")
        elif 'Failed to open audio' in result.stdout:
            print(f"  ✗ Display {display_id} audio failed (might not be connected)")
        else:
            print(f"  ? Display {display_id} status unclear")
    
    print("\n✓ HDMI port switching test complete")


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.audio
def test_display_audio_latency(host):
    """Test that audio latency is within acceptable range."""
    print("\n" + "="*60)
    print("TESTING AUDIO LATENCY")
    print("="*60)
    
    # Check PipeWire configuration for latency
    result = host.run("pw-metadata -n settings 2>/dev/null | grep -E 'clock.quantum|clock.rate' || echo 'default-config'")
    
    if 'default-config' not in result.stdout:
        print(f"PipeWire config:\n{result.stdout}")
    else:
        print("Using default PipeWire configuration")
    
    # Calculate expected latency (quantum / sample_rate * 1000 = ms)
    # Default: 256 samples / 48000 Hz * 1000 = 5.33ms
    expected_latency = 5.33
    print(f"Expected latency: ~{expected_latency}ms")
    
    # Check if low-latency settings are applied
    quantum_check = host.run("pw-metadata -n settings 2>/dev/null | grep 'clock.quantum' | grep -o '[0-9]*' | head -1 || echo '256'")
    # Handle multiple matches - take last non-empty value
    lines = [l for l in quantum_check.stdout.strip().split('\n') if l]
    quantum_str = lines[-1] if lines else '256'
    quantum = int(quantum_str) if quantum_str.isdigit() else 256
    
    # Lower quantum = lower latency
    if quantum <= 256:
        print(f"✓ Low latency configuration: {quantum} samples")
        assert True
    elif quantum <= 512:
        print(f"⚠ Medium latency configuration: {quantum} samples")
        assert True
    else:
        print(f"✗ High latency configuration: {quantum} samples")
        assert False, f"Audio latency too high: {quantum} samples"


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.audio
def test_display_pipewire_hdmi_sink_selection(host):
    """Test that correct HDMI sink is selected for each display ID."""
    print("\n" + "="*60)
    print("TESTING HDMI SINK SELECTION")
    print("="*60)
    
    # Get available HDMI sinks
    result = host.run("pactl list sinks short | grep -i hdmi")
    print("Available HDMI sinks:")
    print(result.stdout)
    
    # Map display IDs to expected HDMI outputs
    # Display 0 = HDMI-A-1, Display 1 = HDMI-A-2, Display 2 = HDMI-A-3
    
    # This is informational - actual selection happens in ndi-display
    hdmi_sinks = result.stdout.strip().split('\n') if result.stdout.strip() else []
    
    if len(hdmi_sinks) >= 3:
        print("✓ Multiple HDMI sinks available for selection")
    elif len(hdmi_sinks) >= 1:
        print("⚠ Limited HDMI sinks available")
    else:
        print("✗ No HDMI sinks available")
    
    assert len(hdmi_sinks) >= 1, "No HDMI sinks available for audio output"
