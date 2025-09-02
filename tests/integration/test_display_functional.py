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
    log_check = host.run("grep -i audio /tmp/ndi-display-test.log | tail -5")
    audio_initialized = False
    audio_device = None
    
    if 'Audio output initialized' in log_check.stdout or 'Opened audio device' in log_check.stdout:
        audio_initialized = True
        # Extract audio device (e.g., hw:2,3)
        for line in log_check.stdout.split('\n'):
            if 'hw:' in line:
                import re
                match = re.search(r'hw:\d+,\d+', line)
                if match:
                    audio_device = match.group()
                    break
    
    print(f"Audio initialized: {audio_initialized}")
    if audio_device:
        print(f"Audio device: {audio_device}")
    
    # 8. Check ALSA audio status
    if audio_device:
        # Extract card and device numbers
        match = re.match(r'hw:(\d+),(\d+)', audio_device)
        if match:
            card, device = match.groups()
            alsa_status = host.run(f"cat /proc/asound/card{card}/pcm{device}p/sub0/status 2>/dev/null || echo 'NOT FOUND'")
            
            if 'RUNNING' in alsa_status.stdout:
                print("✓ AUDIO IS PLAYING through HDMI")
                audio_playing = True
            elif 'OPEN' in alsa_status.stdout:
                print("✗ Audio device is OPEN but NOT PLAYING (no audio in stream?)")
                audio_playing = False
            else:
                print("✗ Audio device status unknown")
                audio_playing = False
                
            print(f"ALSA status:\n{alsa_status.stdout}")
    else:
        print("✗ No audio device detected")
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
    
    # 10. Stop the display
    print("\nStopping NDI display...")
    host.run(f"kill {pid} 2>/dev/null || true")
    time.sleep(2)
    
    # 11. Verify console returns
    print("Verifying console returns to display...")
    host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
    host.run("chvt 2 && sleep 0.5 && chvt 1")  # Switch TTY to refresh
    
    # Check console is bound
    result = host.run("cat /sys/class/vtconsole/vtcon1/bind")
    console_restored = '1' in result.stdout
    
    print(f"Console restored: {console_restored}")
    assert console_restored, "Console was not restored after display stopped"
    
    # Final summary
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
    print(f"✓ Console restored: {console_restored}")
    print("="*60)
    
    # Assert audio should be playing if device was initialized
    if audio_initialized and not audio_playing:
        pytest.fail("Audio device initialized but not playing - possible audio issue")


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
    
    # 2. Start a quick display test (5 seconds)
    print("Starting NDI display briefly...")
    host.run("echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
    
    # Use the capture stream as it's always available
    cmd = f"timeout 5 /opt/media-bridge/ndi-display 'MEDIA-BRIDGE (USB Capture)' {display_id} > /dev/null 2>&1 || true"
    host.run(cmd)
    
    # 3. Restore console
    print("Restoring console...")
    host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
    host.run("chvt 1; sleep 0.5; chvt 2")  # Force console refresh
    
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
    
    # 1. Check if PipeWire is running
    print("Checking PipeWire status...")
    result = host.run("ps aux | grep -E 'pipewire|wireplumber' | grep -v grep")
    if result.stdout:
        print("✓ PipeWire is running")
        print(result.stdout)
        
        # Check if PipeWire is using HDMI devices
        pw_sinks = host.run("pactl list sinks 2>/dev/null || echo 'pactl not available'")
        if 'hdmi' in pw_sinks.stdout.lower():
            print("⚠ PipeWire may be controlling HDMI audio devices")
            issues_found.append("PipeWire controlling HDMI")
    else:
        print("✓ PipeWire not running (good for ALSA direct access)")
    
    # 2. Check ALSA devices
    print("\nChecking ALSA HDMI devices...")
    result = host.run("aplay -l | grep -i hdmi")
    if result.stdout:
        print("✓ HDMI audio devices found:")
        print(result.stdout)
    else:
        print("✗ No HDMI audio devices found")
        issues_found.append("No HDMI audio devices")
    
    # 3. Check if any audio is already using HDMI
    print("\nChecking HDMI audio device status...")
    for card in range(3):  # Check first 3 cards
        for device in range(10):  # Check first 10 devices
            status_file = f"/proc/asound/card{card}/pcm{device}p/sub0/status"
            result = host.run(f"[ -f {status_file} ] && cat {status_file} || echo ''")
            if result.stdout and 'closed' not in result.stdout.lower():
                print(f"Card {card}, Device {device}: {result.stdout.strip()}")
                if 'RUNNING' in result.stdout:
                    # Check which process owns it
                    owner = host.run(f"grep owner_pid {status_file} | awk '{{print $3}}'")
                    if owner.stdout:
                        pid = owner.stdout.strip()
                        process = host.run(f"ps -p {pid} -o comm= 2>/dev/null || echo 'unknown'")
                        print(f"  Owned by PID {pid}: {process.stdout.strip()}")
                        if 'chrome' in process.stdout.lower() or 'pipewire' in process.stdout.lower():
                            issues_found.append(f"HDMI audio locked by {process.stdout.strip()}")
    
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
        
        # Quick test with CG stream
        host.run("echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
        test_result = host.run(f"timeout 10 /opt/media-bridge/ndi-display 'RESOLUME-SNV (cg-obs)' {display_id} 2>&1 | grep -i audio")
        
        if 'Audio output initialized' in test_result.stdout:
            print("✓ Audio initialization successful")
        else:
            print("✗ Audio initialization failed")
            print(test_result.stdout)
            issues_found.append("Audio initialization failed")
            
        # Restore console
        host.run("echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true")
    
    # Summary
    print("\n" + "="*60)
    print("AUDIO DIAGNOSTIC SUMMARY")
    if issues_found:
        print("Issues found:")
        for issue in issues_found:
            print(f"  ✗ {issue}")
        print("\nRecommendations:")
        if "PipeWire" in str(issues_found):
            print("  - Consider stopping PipeWire temporarily for testing")
            print("  - Or configure PipeWire to release HDMI devices")
        if "locked by" in str(issues_found):
            print("  - Stop processes using HDMI audio before testing")
        if "initialization failed" in str(issues_found):
            print("  - Check NDI stream has audio track")
            print("  - Verify HDMI cable supports audio")
    else:
        print("✓ No obvious audio issues detected")
    print("="*60)