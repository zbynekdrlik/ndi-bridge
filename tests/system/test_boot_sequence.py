"""
System test for complete boot sequence.

Tests that the system boots and becomes fully operational.
"""

import pytest
import time


@pytest.mark.system
@pytest.mark.slow
def test_complete_boot_sequence(host):
    """Test that system completes boot and all services are operational."""
    # Check system has finished booting
    boot_result = host.run("systemctl is-system-running")
    acceptable_states = ["running", "degraded"]  # degraded ok for non-critical services
    assert boot_result.stdout.strip() in acceptable_states, f"System state: {boot_result.stdout}"
    
    # Verify uptime (system has been up for at least 30 seconds)
    uptime_result = host.run("cat /proc/uptime | cut -d. -f1")
    uptime = int(uptime_result.stdout.strip())
    assert uptime > 30, f"System uptime too short: {uptime}s"
    
    # Check critical services are running
    critical_services = [
        "systemd-networkd",  # Network
        "ndi-capture",       # Capture service
        "nginx",            # Web interface
        "sshd"              # SSH access
    ]
    
    for service_name in critical_services:
        service = host.service(service_name)
        assert service.is_running, f"{service_name} not running after boot"
    
    # Verify network is configured
    ip_result = host.run("hostname -I")
    assert ip_result.stdout.strip(), "No IP address after boot"
    
    # Check capture has started
    capture_state_file = host.file("/var/run/media-bridge/capture_state")
    assert capture_state_file.exists, "Capture state not initialized"
    
    # Verify welcome screen is displayed (TTY2)
    tty2_result = host.run("ps aux | grep -E 'media-bridge-welcome.*tty2'")
    assert tty2_result.succeeded, "Welcome screen not running on TTY2"


def test_auto_start_enabled_services(host):
    """Test that all required systemd services are enabled for auto-start."""
    required_services = [
        "ndi-capture",      # Video capture service
        "nginx",            # Web interface
        "systemd-networkd", # Network configuration
        "ssh"               # Remote access
    ]
    
    for service_name in required_services:
        service = host.service(service_name)
        assert service.is_enabled, f"{service_name} not enabled for auto-start"


def test_runtime_directories_created(host):
    """Test that runtime directories are created during boot."""
    runtime_dirs = [
        "/var/run/media-bridge",
        "/var/log/media-bridge",
        "/tmp"
    ]
    
    for dir_path in runtime_dirs:
        directory = host.file(dir_path)
        assert directory.exists, f"Runtime directory {dir_path} not created"
        assert directory.is_directory, f"{dir_path} is not a directory"