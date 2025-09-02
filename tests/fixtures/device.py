"""
Shared fixtures for NDI Bridge device operations.

Provides reusable fixtures for common device interactions.
"""

import pytest
import time


@pytest.fixture
def restart_service(host):
    """Fixture to restart any systemd service."""
    def _restart(service_name, wait=2):
        """
        Restart a systemd service and wait.
        
        Args:
            service_name: Name of the service to restart
            wait: Seconds to wait after restart (default: 2)
        """
        result = host.run(f"systemctl restart {service_name}")
        if not result.succeeded:
            pytest.fail(f"Failed to restart {service_name}: {result.stderr}")
        time.sleep(wait)
        return result
    return _restart


@pytest.fixture
def service_status(host):
    """Fixture to check service status."""
    def _status(service_name):
        """Get detailed status of a service."""
        return {
            "enabled": host.service(service_name).is_enabled,
            "running": host.service(service_name).is_running,
            "active": host.run(f"systemctl is-active {service_name}").stdout.strip(),
            "pid": host.run(f"systemctl show -p MainPID {service_name}").stdout.strip()
        }
    return _status


@pytest.fixture
def clean_runtime_files(host):
    """Fixture to clean runtime files before test."""
    def _clean(pattern="/var/run/ndi-bridge/*"):
        """Remove runtime files matching pattern."""
        host.run(f"rm -f {pattern}")
    return _clean


@pytest.fixture
def wait_for_file(host):
    """Fixture to wait for a file to appear."""
    def _wait(filepath, timeout=30):
        """
        Wait for a file to exist.
        
        Args:
            filepath: Path to the file
            timeout: Maximum seconds to wait
            
        Returns:
            True if file appeared, False if timeout
        """
        start = time.time()
        while time.time() - start < timeout:
            if host.file(filepath).exists:
                return True
            time.sleep(1)
        return False
    return _wait


@pytest.fixture
def capture_metrics(host):
    """Fixture to read current capture metrics."""
    def _metrics():
        """Read all capture metrics as dictionary."""
        metrics = {}
        metrics_dir = "/var/run/ndi-bridge"
        
        # Read numeric metrics
        for metric in ["fps", "frames_captured", "frames_dropped"]:
            filepath = f"{metrics_dir}/{metric}"
            if host.file(filepath).exists:
                content = host.file(filepath).content_string.strip()
                try:
                    metrics[metric] = float(content) if metric == "fps" else int(content)
                except ValueError:
                    metrics[metric] = None
            else:
                metrics[metric] = None
        
        # Read state
        state_file = f"{metrics_dir}/capture_state"
        if host.file(state_file).exists:
            metrics["state"] = host.file(state_file).content_string.strip()
        else:
            metrics["state"] = None
            
        return metrics
    return _metrics


@pytest.fixture
def system_uptime(host):
    """Fixture to get system uptime in seconds."""
    def _uptime():
        """Get system uptime in seconds."""
        result = host.run("cat /proc/uptime")
        if result.succeeded:
            return float(result.stdout.split()[0])
        return None
    return _uptime