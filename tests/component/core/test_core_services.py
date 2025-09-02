"""
Atomic tests for core system services.

Tests fundamental services required for NDI Bridge operation.
"""

import pytest


def test_systemd_is_running(host):
    """Test that systemd is the init system."""
    result = host.run("ps -p 1 -o comm=")
    assert result.stdout.strip() == "systemd", "systemd is not PID 1"


def test_ssh_service_enabled(host):
    """Test that SSH service is enabled."""
    service = host.service("ssh")
    assert service.is_enabled, "SSH service is not enabled"


def test_ssh_service_running(host):
    """Test that SSH service is running."""
    service = host.service("ssh")
    assert service.is_running, "SSH service is not running"


def test_nginx_service_enabled(host):
    """Test that nginx web server is enabled."""
    service = host.service("nginx")
    assert service.is_enabled, "nginx service is not enabled"


def test_nginx_service_running(host):
    """Test that nginx web server is running."""
    service = host.service("nginx")
    assert service.is_running, "nginx service is not running"


def test_nginx_listening_on_port_80(host):
    """Test that nginx is listening on port 80."""
    socket = host.socket("tcp://0.0.0.0:80")
    assert socket.is_listening, "nginx not listening on port 80"


@pytest.mark.critical
def test_ndi_capture_service_enabled(host):
    """Test that NDI capture service is enabled."""
    service = host.service("ndi-capture")
    assert service.is_enabled, "ndi-capture service is not enabled"


@pytest.mark.critical  
def test_ndi_capture_service_running(host):
    """Test that NDI capture service is running."""
    service = host.service("ndi-capture")
    assert service.is_running, "ndi-capture service is not running"


def test_systemd_networkd_enabled(host):
    """Test that systemd-networkd is enabled."""
    service = host.service("systemd-networkd")
    assert service.is_enabled, "systemd-networkd is not enabled"


def test_systemd_networkd_running(host):
    """Test that systemd-networkd is running."""
    service = host.service("systemd-networkd")
    assert service.is_running, "systemd-networkd is not running"


def test_systemd_resolved_enabled(host):
    """Test that systemd-resolved is enabled."""
    service = host.service("systemd-resolved")
    assert service.is_enabled, "systemd-resolved is not enabled"


def test_systemd_resolved_running(host):
    """Test that systemd-resolved is running."""
    service = host.service("systemd-resolved")
    assert service.is_running, "systemd-resolved is not running"