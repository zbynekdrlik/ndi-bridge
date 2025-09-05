"""
Pytest configuration and fixtures for Media Bridge testing.

This module provides shared fixtures and configuration for all tests.
Following the principle of atomic testing, fixtures are designed to be
composable and focused on single responsibilities.
"""

import os
import sys
import pytest
from pathlib import Path
from typing import Dict, List, Optional
import testinfra

# Add fixtures directory to path for imports
sys.path.insert(0, str(Path(__file__).parent / "fixtures"))

# Import shared fixtures to make them available to all tests
from fixtures.device import *  # noqa: F401, F403


def pytest_addoption(parser):
    """Add custom command line options for Media Bridge testing."""
    # IMPORTANT: IP address MUST be provided as command-line parameter
    # NO config files, NO environment variables - only command line!
    
    parser.addoption(
        "--host",
        action="store",
        required=True,
        help="Media Bridge device IP address (REQUIRED - must be provided as command line parameter)",
    )
    parser.addoption(
        "--multi-hosts",
        action="store",
        help="Comma-separated list of hosts for parallel testing",
    )
    parser.addoption(
        "--ssh-user",
        action="store",
        default="root",
        help="SSH username for device access (default: root)",
    )
    parser.addoption(
        "--ssh-pass",
        action="store",
        default="newlevel",
        help="SSH password for device access (default: newlevel)",
    )
    parser.addoption(
        "--ssh-key",
        action="store",
        default=None,
        help="Path to SSH key for passwordless access",
    )


def pytest_configure(config):
    """Configure pytest with custom settings."""
    # No config files - everything from command line only!
    config.test_config = {}


@pytest.fixture(scope="session")
def device_config(request) -> Dict:
    """
    Provides device configuration from command line or config file.
    
    Returns:
        Dictionary with device configuration including IP, credentials, etc.
    """
    return {
        "host": request.config.getoption("--host"),
        "ssh_user": request.config.getoption("--ssh-user"),
        "ssh_pass": request.config.getoption("--ssh-pass"),
        "ssh_key": request.config.getoption("--ssh-key"),
    }


@pytest.fixture(scope="session")
def host(device_config):
    """
    Primary fixture for accessing the Media Bridge device via SSH.
    
    This fixture establishes SSH connection to the device
    and returns a testinfra Host object for test execution.
    
    Note: To handle changing SSH host keys (when same IP has different device),
    add StrictHostKeyChecking=no to the connection string for test environments.
    """
    # Build connection string
    # Note: SSH host key handling should be done via ~/.ssh/config or by clearing known_hosts
    if device_config["ssh_key"]:
        conn_str = f"ssh://{device_config['ssh_user']}@{device_config['host']}?ssh_identity_file={device_config['ssh_key']}"
    else:
        conn_str = f"ssh://{device_config['ssh_user']}@{device_config['host']}?password={device_config['ssh_pass']}"
    
    # Get testinfra host
    host = testinfra.get_host(conn_str)
    
    return host




@pytest.fixture
def ndi_version(host) -> str:
    """Get the Media Bridge version from the device."""
    cmd = host.run("cat /etc/media-bridge-version 2>/dev/null || echo 'unknown'")
    return cmd.stdout.strip()


@pytest.fixture
def system_info(host) -> Dict:
    """Gather system information for test context."""
    return {
        "kernel": host.run("uname -r").stdout.strip(),
        "arch": host.run("uname -m").stdout.strip(),
        "hostname": host.run("hostname").stdout.strip(),
        "uptime": host.run("uptime -p").stdout.strip(),
    }


@pytest.fixture
def usb_devices(host) -> List[str]:
    """List connected USB devices."""
    cmd = host.run("lsusb")
    return cmd.stdout.strip().split("\n") if cmd.succeeded else []


@pytest.fixture
def network_interfaces(host) -> List[str]:
    """List available network interfaces."""
    cmd = host.run("ip -o link show | awk '{print $2}' | sed 's/:$//'")
    return cmd.stdout.strip().split("\n") if cmd.succeeded else []


@pytest.fixture
def systemd_units(host) -> List[str]:
    """List all systemd units."""
    cmd = host.run("systemctl list-units --all --no-pager --plain | awk '{print $1}'")
    return cmd.stdout.strip().split("\n") if cmd.succeeded else []


# Markers for test categorization
def pytest_collection_modifyitems(config, items):
    """Automatically add markers based on test file names."""
    for item in items:
        # Add markers based on test file location
        test_file = str(item.fspath)
        
        if "critical" in test_file:
            item.add_marker(pytest.mark.critical)
        if "capture" in test_file:
            item.add_marker(pytest.mark.capture)
        if "display" in test_file:
            item.add_marker(pytest.mark.display)
        if "audio" in test_file:
            item.add_marker(pytest.mark.audio)
        if "network" in test_file:
            item.add_marker(pytest.mark.network)
        if "web" in test_file:
            item.add_marker(pytest.mark.web)
        if "timesync" in test_file:
            item.add_marker(pytest.mark.timesync)


# Test result hooks
def pytest_runtest_makereport(item, call):
    """Add extra information to test reports."""
    # Temporarily disabled - causing hangs with certain test configurations
    pass