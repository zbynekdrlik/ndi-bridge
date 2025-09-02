"""
Atomic tests for DHCP client functionality.

Tests network configuration via DHCP.
"""

import pytest
import ipaddress


def test_dhcp_client_service_enabled(host):
    """Test that DHCP client service is enabled."""
    # systemd-networkd handles DHCP on modern systems
    service = host.service("systemd-networkd")
    assert service.is_enabled, "Network service not enabled"


def test_dhcp_client_service_running(host):
    """Test that DHCP client service is running."""
    service = host.service("systemd-networkd")
    assert service.is_running, "Network service not running"


def test_primary_interface_has_ip(host):
    """Test that primary network interface has an IP address."""
    # Get primary interface (usually eth0 or enp*)
    result = host.run("ip route | grep default | awk '{print $5}' | head -1")
    interface = result.stdout.strip()
    
    assert interface, "No default network interface found"
    
    # Check if interface has IP
    ip_result = host.run(f"ip -4 addr show {interface} | grep inet")
    assert ip_result.succeeded, f"No IPv4 address on {interface}"


def test_ip_address_is_valid(host):
    """Test that assigned IP address is valid."""
    result = host.run("hostname -I | awk '{print $1}'")
    ip_str = result.stdout.strip()
    
    try:
        ip = ipaddress.IPv4Address(ip_str)
        assert not ip.is_loopback, "IP is loopback address"
        assert not ip.is_link_local, "IP is link-local address"
    except ipaddress.AddressValueError:
        pytest.fail(f"Invalid IP address: {ip_str}")


def test_default_gateway_configured(host):
    """Test that default gateway is configured."""
    result = host.run("ip route | grep '^default'")
    assert result.succeeded, "No default gateway configured"


def test_dns_resolver_configured(host):
    """Test that DNS resolver is configured."""
    resolv = host.file("/etc/resolv.conf")
    assert resolv.exists, "No resolv.conf file"
    assert "nameserver" in resolv.content_string, "No DNS nameserver configured"


@pytest.mark.network
def test_network_connectivity(host):
    """Test basic network connectivity."""
    # Ping gateway
    gateway_result = host.run("ip route | grep default | awk '{print $3}' | head -1")
    gateway = gateway_result.stdout.strip()
    
    if gateway:
        ping_result = host.run(f"ping -c 1 -W 2 {gateway}")
        assert ping_result.succeeded, f"Cannot reach gateway {gateway}"