"""
Pytest configuration and fixtures for NDI Bridge testing.

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

# Add fixtures directory to path for imports
sys.path.insert(0, str(Path(__file__).parent / "fixtures"))

# Import shared fixtures to make them available to all tests
from fixtures.device import *  # noqa: F401, F403


def pytest_addoption(parser):
    """Add custom command line options for NDI Bridge testing."""
    parser.addoption(
        "--host",
        action="store",
        default="10.77.9.143",
        help="NDI Bridge device IP address or hostname",
    )
    parser.addoption(
        "--hosts",
        action="store",
        help="Comma-separated list of hosts for parallel testing",
    )
    parser.addoption(
        "--ssh-user",
        action="store",
        default="root",
        help="SSH username for device access",
    )
    parser.addoption(
        "--ssh-pass",
        action="store",
        default="newlevel",
        help="SSH password for device access",
    )
    parser.addoption(
        "--ssh-key",
        action="store",
        default=None,
        help="Path to SSH key for passwordless access",
    )
    parser.addoption(
        "--skip-readonly-check",
        action="store_true",
        default=False,
        help="Skip the critical read-only filesystem check (NOT RECOMMENDED)",
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
        "skip_readonly": request.config.getoption("--skip-readonly-check"),
    }


@pytest.fixture(scope="session")
def host(device_config):
    """
    Primary fixture for accessing the NDI Bridge device via SSH.
    
    This fixture:
    1. Establishes SSH connection to the device
    2. Performs critical read-only filesystem check
    3. Returns a testinfra Host object for test execution
    
    CRITICAL: The read-only filesystem check is mandatory per CLAUDE.md
    """
    # Build connection string
    if device_config["ssh_key"]:
        conn_str = f"ssh://{device_config['ssh_user']}@{device_config['host']}?ssh_identity_file={device_config['ssh_key']}"
    else:
        conn_str = f"ssh://{device_config['ssh_user']}@{device_config['host']}?password={device_config['ssh_pass']}"
    
    # Get testinfra host
    host = testinfra.get_host(conn_str)
    
    # CRITICAL: Verify filesystem is read-only (unless explicitly skipped)
    if not device_config["skip_readonly"]:
        mount_info = host.mount_point("/")
        assert mount_info.exists, "Root filesystem not found"
        assert "ro" in mount_info.options, (
            "CRITICAL: Root filesystem is NOT read-only!\n"
            "The device must have a read-only filesystem for production.\n"
            "Current mount options: {}".format(mount_info.options)
        )
    
    return host


@pytest.fixture
def require_readonly(host):
    """
    Fixture that explicitly requires read-only filesystem.
    Use this in tests that MUST have read-only filesystem.
    """
    mount_info = host.mount_point("/")
    if "ro" not in mount_info.options:
        pytest.skip("Test requires read-only filesystem")
    return True


@pytest.fixture
def require_readwrite(host):
    """
    Fixture that requires read-write filesystem.
    Use this for tests that need to modify system files.
    """
    mount_info = host.mount_point("/")
    if "rw" not in mount_info.options:
        pytest.skip("Test requires read-write filesystem")
    return True


@pytest.fixture
def ndi_version(host) -> str:
    """Get the NDI Bridge version from the device."""
    cmd = host.run("cat /etc/ndi-bridge-version 2>/dev/null || echo 'unknown'")
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
    if call.when == "call":
        if hasattr(item, "funcargs"):
            if "host" in item.funcargs:
                host = item.funcargs["host"]
                # Add device info to test metadata
                item.user_properties.append(
                    ("device", host.run("hostname").stdout.strip())
                )
                item.user_properties.append(
                    ("version", host.run("cat /etc/ndi-bridge-version 2>/dev/null || echo 'unknown'").stdout.strip())
                )