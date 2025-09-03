"""
Functional tests for NDI display with actual stream playback.

These tests actually play NDI streams and verify video/audio output.
Based on the original bash test_display.sh functionality.
"""

import pytest
import time
import re


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.functional
def test_display_stream_playback_with_audio(host):
    """
    FUNCTIONAL TEST: Play CG stream for 30 seconds with audio verification.
    User should see video on HDMI monitor and hear audio.
    """
    print("\n" + "="*60)
    print("FUNCTIONAL DISPLAY TEST - YOU SHOULD SEE AND HEAR OUTPUT")
    print("="*60)
    
    # 1. Find available CG/NDI streams
    print("Finding available NDI streams...")
    result = host.run("/opt/media-bridge/ndi-display list")
    assert result.succeeded, "Failed to list NDI streams"
    
    # Look for CG streams (prefer cg-obs or similar)
    cg_stream = None
    for line in result.stdout.split('\n'):
        if 'cg-obs' in line.lower() or 'cg' in line.lower():
            # Extract the full stream name (format: "N: STREAM NAME")
            if ': ' in line and not line.startswith('['):
                # Split on ": " and take everything after the first colon
                parts = line.split(': ', 1)
                if len(parts) > 1:
                    cg_stream = parts[1].strip()
                    break
    
    if not cg_stream:
        # Fallback to any available stream
        for line in result.stdout.split('\n'):
            if ': ' in line and 'NDI' in line and not line.startswith('['):
                parts = line.split(': ', 1)
                if len(parts) > 1:
                    cg_stream = parts[1].strip()
                    break
    
    assert cg_stream, "No NDI streams available for testing"
    print(f"Using stream: {cg_stream}")
    
    # 2. Check which display has monitor connected
    result = host.run("for i in /sys/class/drm/*/status; do echo \"$(basename $(dirname $i)): $(cat $i)\"; done")
    connected_display = None
    display_id = None
    
    for line in result.stdout.split('\n'):
        if 'connected' in line and 'disconnected' not in line:
            # Extract display info (e.g., card1-HDMI-A-2)
            parts = line.split(':')
            if parts:
                card_info = parts[0].strip()
                # Map to display ID (HDMI-A-1 = 0, HDMI-A-2 = 1, etc.)
                if 'HDMI-A-1' in card_info:
                    display_id = 0
                elif 'HDMI-A-2' in card_info:
                    display_id = 1
                elif 'HDMI-A-3' in card_info:
                    display_id = 2
                connected_display = card_info
                break
    
    # If no monitor detected, use default display 1 (HDMI-A-2)
    # Monitor might be off or connected later - NDI should still work
    if not connected_display:
        print("WARNING: No monitor detected (may be powered off or connected later)")
        print("Using default display 1 (HDMI-A-2) for testing")
        display_id = 1
        connected_display = "HDMI-A-2 (headless)"
    else:
        assert display_id is not None, "Could not determine display ID"
        print(f"Monitor connected to: {connected_display} (display {display_id})")
    
    # 3. Stop any existing display service and unbind console
    print(f"Preparing display {display_id}...")
    host.run(f"systemctl stop ndi-display@{display_id} 2>/dev/null || true")
    host.run("echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
    time.sleep(2)
    
    # 4. Start NDI display with the CG stream
    print(f"Starting NDI display with stream: {cg_stream}")
    # Use nohup to run in background
    cmd = f"nohup /opt/media-bridge/ndi-display '{cg_stream}' {display_id} > /tmp/ndi-display-test.log 2>&1 & echo $!"
    result = host.run(cmd)
    pid = result.stdout.strip()
    print(f"NDI display started with PID: {pid}")
    
    # Ensure cleanup happens even if test fails
    try:
        # 5. Wait for stream to establish
        print("Waiting for stream to establish...")
        time.sleep(5)
        
        # 6. Verify video is being displayed (check for running process and frames)
        result = host.run(f"ps -p {pid} > /dev/null && echo 'RUNNING' || echo 'STOPPED'")
        assert 'RUNNING' in result.stdout, "NDI display process died"
        
        # Check log for successful connection
        result = host.run("tail -20 /tmp/ndi-display-test.log")
        assert 'Connected to NDI source' in result.stdout or 'Displaying on' in result.stdout, \
            "NDI display did not connect to stream"
        
        # 7. Verify audio device is opened
        print("Checking audio output...")
        log_check = host.run("grep -i 'audio' /tmp/ndi-display-test.log | tail -10")
        audio_initialized = False
        
        # Check for generic audio initialization message (works with both ALSA and PipeWire)
        if 'Audio output initialized' in log_check.stdout:
            audio_initialized = True
            print("✓ Audio output initialized")
        elif 'PipeWire audio' in log_check.stdout:
            audio_initialized = True
            print("✓ PipeWire audio initialized")
        
        print(f"Audio initialized: {audio_initialized}")
        
        # 8. Check PipeWire audio status
        audio_playing = False
        if audio_initialized:
            # Check if ndi-display appears in PipeWire clients
            pw_status = host.run("pw-cli list-objects 2>/dev/null | grep -A5 'ndi-display' || echo 'PipeWire not available'")
            
            if 'ndi-display' in pw_status.stdout:
                print("✓ NDI Display registered with PipeWire")
                
                # Check if stream is active
                stream_status = host.run("pw-cli dump short 2>/dev/null | grep 'ndi-display.*STREAMING' || echo ''")
                if 'STREAMING' in stream_status.stdout:
                    print("✓ AUDIO IS PLAYING through PipeWire")
                    audio_playing = True
                else:
                    # Alternative check - see if ndi-display node exists
                    node_check = host.run("pactl list clients 2>/dev/null | grep -i 'ndi-display' || echo ''")
                    if 'ndi-display' in node_check.stdout:
                        print("✓ Audio stream active (PipeWire client connected)")
                        audio_playing = True
                    else:
                        print("✗ Audio stream not active")
                        audio_playing = False
            else:
                print("✗ NDI Display not found in PipeWire")
                audio_playing = False
        else:
            print("✗ PipeWire audio not initialized")
            audio_playing = False
        
        # 9. Monitor for 30 seconds
        print("\n" + "="*60)
        print("MONITORING STREAM FOR 30 SECONDS")
        print("YOU SHOULD SEE VIDEO ON HDMI MONITOR")
        if audio_playing:
            print("YOU SHOULD HEAR AUDIO FROM MONITOR SPEAKERS")
        else:
            print("WARNING: AUDIO NOT PLAYING - CHECK STREAM HAS AUDIO")
        print("="*60)
        
        # Get initial frame count
        initial_log = host.run("tail -5 /tmp/ndi-display-test.log | grep -i frames || echo 'No frame info'")
        print(f"Initial status: {initial_log.stdout.strip()}")
        
        # Wait 30 seconds
        for i in range(6):
            time.sleep(5)
            print(f"Elapsed: {(i+1)*5} seconds...")
            if (i+1) % 2 == 0:
                # Check frame count every 10 seconds
                status = host.run("tail -1 /tmp/ndi-display-test.log | grep -i frames || echo 'No update'")
                print(f"  Status: {status.stdout.strip()}")
        
        # Get final frame count
        final_log = host.run("tail -5 /tmp/ndi-display-test.log | grep -i frames || echo 'No frame info'")
        print(f"Final status: {final_log.stdout.strip()}")
        
        # Final summary (before cleanup)
        print("\n" + "="*60)
        print("FUNCTIONAL TEST COMPLETE")
        print(f"✓ Stream displayed: {cg_stream}")
        print(f"✓ Display used: {connected_display}")
        if audio_initialized:
            if audio_playing:
                print("✓ Audio was PLAYING")
            else:
                print("✗ Audio device opened but NOT PLAYING (no audio in stream?)")
        else:
            print("✗ Audio was NOT initialized")
        
        # Assert audio should be playing if device was initialized
        if audio_initialized and not audio_playing:
            pytest.fail("Audio device initialized but not playing - possible audio issue")
            
    finally:
        # ALWAYS cleanup, even if test fails
        print("\nCLEANUP: Stopping NDI display...")
        host.run(f"kill {pid} 2>/dev/null || true")
        time.sleep(2)
        
        # Clear any display configuration
        host.run(f"rm -f /var/run/ndi-display/display-{display_id}.status 2>/dev/null || true")
        host.run(f"rm -f /etc/ndi-display/display-{display_id}.conf 2>/dev/null || true")
        
        # Restore console
        print("CLEANUP: Restoring console...")
        host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        host.run(f"chvt {display_id + 1} && sleep 0.5 && chvt 1")  # Switch TTY to refresh
        
        # Verify console is restored
        result = host.run("cat /sys/class/vtconsole/vtcon1/bind")
        console_restored = '1' in result.stdout
        print(f"CLEANUP: Console restored: {console_restored}")
        
        if not console_restored:
            # Force console restoration
            host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind")
            host.run("setterm -blank poke > /dev/tty2 2>/dev/null || true")
        
        print("="*60)


@pytest.mark.integration
@pytest.mark.display
@pytest.mark.functional
def test_display_console_recovery(host):
    """
    Test that Linux console properly returns after NDI display stops.
    This ensures the system remains usable after display testing.
    """
    print("\n" + "="*60)
    print("TESTING CONSOLE RECOVERY")
    print("="*60)
    
    # Find connected display
    result = host.run("for i in /sys/class/drm/*/status; do echo \"$(basename $(dirname $i)): $(cat $i)\"; done")
    display_id = None
    
    for line in result.stdout.split('\n'):
        if 'connected' in line and 'disconnected' not in line:
            if 'HDMI-A-1' in line:
                display_id = 0
            elif 'HDMI-A-2' in line:
                display_id = 1
            elif 'HDMI-A-3' in line:
                display_id = 2
            break
    
    if display_id is None:
        # Use default display 1 even if no monitor detected
        display_id = 1
        print("No monitor detected, using default display 1 for console recovery test")
    
    print(f"Testing with display {display_id}")
    
    # 1. Ensure console is initially bound
    host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
    initial_bind = host.run("cat /sys/class/vtconsole/vtcon1/bind").stdout.strip()
    print(f"Initial console bind state: {initial_bind}")
    
    try:
        # 2. Start a quick display test (5 seconds)
        print("Starting NDI display briefly...")
        host.run("echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        
        # Use the capture stream as it's always available
        cmd = f"timeout 5 /opt/media-bridge/ndi-display 'MEDIA-BRIDGE (USB Capture)' {display_id} > /dev/null 2>&1 || true"
        host.run(cmd)
        
    finally:
        # 3. Always restore console
        print("Restoring console...")
        host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        host.run("chvt 1; sleep 0.5; chvt 2")  # Force console refresh
        
        # Clear any leftover display configuration
        host.run(f"rm -f /var/run/ndi-display/display-{display_id}.status 2>/dev/null || true")
        host.run(f"rm -f /etc/ndi-display/display-{display_id}.conf 2>/dev/null || true")
    
    # 4. Verify console is bound
    final_bind = host.run("cat /sys/class/vtconsole/vtcon1/bind").stdout.strip()
    print(f"Final console bind state: {final_bind}")
    
    assert '1' in final_bind, "Console was not properly restored"
    
    # 5. Test that TTY switching works
    result = host.run("chvt 1 && echo 'TTY switch OK' || echo 'TTY switch FAILED'")
    assert 'TTY switch OK' in result.stdout, "TTY switching failed after display test"
    
    print("✓ Console successfully recovered after NDI display")
    print("✓ TTY switching works properly")
    print("="*60)


@pytest.mark.integration  
@pytest.mark.display
@pytest.mark.functional
@pytest.mark.slow
def test_display_audio_diagnosis(host):
    """
    Diagnostic test to identify why audio might not be playing.
    This test checks various audio subsystem components.
    """
    print("\n" + "="*60)
    print("AUDIO DIAGNOSTICS FOR NDI DISPLAY")
    print("="*60)
    
    issues_found = []
    
    # 1. Check if PipeWire is running (REQUIRED for new implementation)
    print("Checking PipeWire status...")
    result = host.run("ps aux | grep -E 'pipewire|wireplumber' | grep -v grep")
    if result.stdout:
        print("✓ PipeWire is running (required)")
        print(result.stdout)
        
        # Check available PipeWire sinks
        pw_sinks = host.run("pactl list sinks short 2>/dev/null || echo 'pactl not available'")
        if pw_sinks.stdout and 'pactl not available' not in pw_sinks.stdout:
            print("✓ PipeWire sinks available:")
            print(pw_sinks.stdout)
    else:
        print("✗ PipeWire not running (REQUIRED for audio)")
        issues_found.append("PipeWire not running")
    
    # 2. Check PipeWire nodes and streams
    print("\nChecking PipeWire audio nodes...")
    result = host.run("pw-cli list-objects Node 2>/dev/null | grep -E 'node.name|media.class' | head -20 || echo 'pw-cli not available'")
    if 'pw-cli not available' not in result.stdout:
        print("PipeWire nodes found:")
        print(result.stdout)
    else:
        print("✗ Cannot query PipeWire nodes")
        issues_found.append("PipeWire CLI not available")
    
    # 3. Check if intercom or other apps are using audio
    print("\nChecking active audio clients...")
    result = host.run("pactl list clients short 2>/dev/null | head -10 || echo ''")
    if result.stdout:
        print("Active PipeWire clients:")
        print(result.stdout)
        if 'chrome' in result.stdout.lower():
            print("⚠ Chrome/Intercom is using audio")
        if 'ndi-display' in result.stdout.lower():
            print("✓ ndi-display already connected to PipeWire")
    
    # 4. Test with a known working stream
    print("\nTesting with known stream...")
    
    # Find display ID
    result = host.run("for i in /sys/class/drm/*/status; do echo \"$(basename $(dirname $i)): $(cat $i)\"; done | grep -v disconnected | head -1")
    if 'connected' in result.stdout:
        if 'HDMI-A-1' in result.stdout:
            display_id = 0
        elif 'HDMI-A-2' in result.stdout:
            display_id = 1
        else:
            display_id = 2
            
        print(f"Testing audio with display {display_id}...")
        
        try:
            # Quick test with CG stream
            host.run("echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
            test_result = host.run(f"timeout 10 /opt/media-bridge/ndi-display 'RESOLUME-SNV (cg-obs)' {display_id} 2>&1 | grep -i 'audio\\|pipewire'")
            
            if 'PipeWire audio' in test_result.stdout:
                print("✓ PipeWire audio initialization successful")
            else:
                print("✗ PipeWire audio initialization failed")
                print(test_result.stdout)
                issues_found.append("PipeWire audio initialization failed")
        finally:
            # Always restore console
            host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
            host.run(f"rm -f /var/run/ndi-display/display-{display_id}.status 2>/dev/null || true")
    
    # Summary
    print("\n" + "="*60)
    print("AUDIO DIAGNOSTIC SUMMARY")
    if issues_found:
        print("Issues found:")
        for issue in issues_found:
            print(f"  ✗ {issue}")
        print("\nRecommendations:")
        if "PipeWire not running" in str(issues_found):
            print("  - Start PipeWire: systemctl start pipewire pipewire-pulse")
            print("  - PipeWire is REQUIRED for audio in ndi-display")
        if "PipeWire CLI not available" in str(issues_found):
            print("  - Install pipewire-utils package")
        if "initialization failed" in str(issues_found):
            print("  - Check NDI stream has audio track")
            print("  - Check PipeWire is running")
            print("  - Check XDG_RUNTIME_DIR is set")
    else:
        print("✓ No obvious audio issues detected")
    print("="*60)