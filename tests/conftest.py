"""
Pytest configuration and fixtures for Media Bridge testing.

This module provides shared fixtures and configuration for all tests.
Following the principle of atomic testing, fixtures are designed to be
composable and focused on single responsibilities.
"""

import os
import sys
import pytest
import yaml
from pathlib import Path
from typing import Dict, List, Optional
import testinfra

# Try to load .env file if it exists
env_file = Path(__file__).parent / ".env"
if env_file.exists():
    from dotenv import load_dotenv
    load_dotenv(env_file)

# Add fixtures directory to path for imports
sys.path.insert(0, str(Path(__file__).parent / "fixtures"))

# Import shared fixtures to make them available to all tests
from fixtures.device import *  # noqa: F401, F403


def pytest_addoption(parser):
    """Add custom command line options for Media Bridge testing."""
    # Priority: 1. Command line, 2. test_config.yaml, 3. Environment, 4. Default
    default_host = "10.77.9.143"
    default_ssh_user = "root"
    default_ssh_pass = "newlevel"
    default_ssh_key = None
    
    # First check test_config.yaml
    config_file = Path(__file__).parent / "test_config.yaml"
    if config_file.exists():
        with open(config_file, "r") as f:
            test_config = yaml.safe_load(f)
            if test_config:
                if "host" in test_config:
                    default_host = test_config["host"]
                if "ssh_user" in test_config:
                    default_ssh_user = test_config["ssh_user"]
                if "ssh_pass" in test_config:
                    default_ssh_pass = test_config["ssh_pass"]
                if "ssh_key" in test_config:
                    # Expand ~ to home directory for SSH key path
                    ssh_key = test_config["ssh_key"]
                    if ssh_key and ssh_key.startswith("~"):
                        ssh_key = os.path.expanduser(ssh_key)
                    default_ssh_key = ssh_key
    
    # Then check environment variable for host
    if os.environ.get("NDI_TEST_HOST"):
        default_host = os.environ.get("NDI_TEST_HOST")
    
    parser.addoption(
        "--host",
        action="store",
        default=default_host,
        help="Media Bridge device IP address or hostname (default: from test_config.yaml, $NDI_TEST_HOST, or 10.77.9.143)",
    )
    parser.addoption(
        "--multi-hosts",
        action="store",
        help="Comma-separated list of hosts for parallel testing",
    )
    parser.addoption(
        "--ssh-user",
        action="store",
        default=default_ssh_user,
        help="SSH username for device access",
    )
    parser.addoption(
        "--ssh-pass",
        action="store",
        default=default_ssh_pass,
        help="SSH password for device access",
    )
    parser.addoption(
        "--ssh-key",
        action="store",
        default=default_ssh_key,
        help="Path to SSH key for passwordless access",
    )


def pytest_configure(config):
    """Configure pytest with custom settings."""
    # Load test configuration if exists
    config_file = Path(__file__).parent / "test_config.yaml"
    if config_file.exists():
        with open(config_file, "r") as f:
            test_config = yaml.safe_load(f)
            config.test_config = test_config
    else:
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