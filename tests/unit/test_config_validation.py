"""
Unit tests for configuration validation.

These tests don't require a device connection.
"""

import pytest
import ipaddress


def test_valid_ip_address_format():
    """Test validation of IP address format."""
    valid_ips = ["192.168.1.1", "10.0.0.1", "172.16.0.1"]
    for ip_str in valid_ips:
        try:
            ip = ipaddress.IPv4Address(ip_str)
            assert True
        except ipaddress.AddressValueError:
            pytest.fail(f"Valid IP rejected: {ip_str}")


def test_invalid_ip_address_format():
    """Test rejection of invalid IP address format."""
    invalid_ips = ["256.1.1.1", "192.168.1", "not.an.ip", ""]
    for ip_str in invalid_ips:
        with pytest.raises(ipaddress.AddressValueError):
            ipaddress.IPv4Address(ip_str)


def test_valid_ndi_name_format():
    """Test validation of NDI stream name format."""
    valid_names = [
        "NDI-BRIDGE",
        "NDI-BRIDGE-01",
        "Camera_1",
        "Studio-Cam-A"
    ]
    
    for name in valid_names:
        # NDI names should be alphanumeric with dash/underscore
        assert name.replace("-", "").replace("_", "").isalnum()
        assert len(name) <= 64  # Reasonable length limit


def test_invalid_ndi_name_format():
    """Test rejection of invalid NDI stream names."""
    invalid_names = [
        "",  # Empty
        "NDI BRIDGE",  # Spaces not recommended
        "NDI@BRIDGE",  # Special characters
        "A" * 65  # Too long
    ]
    
    for name in invalid_names:
        is_valid = (
            name and 
            len(name) <= 64 and 
            name.replace("-", "").replace("_", "").isalnum()
        )
        assert not is_valid, f"Invalid name accepted: {name}"


def test_valid_port_numbers():
    """Test validation of network port numbers."""
    valid_ports = [80, 443, 8080, 5353, 65535]
    
    for port in valid_ports:
        assert 1 <= port <= 65535
        assert isinstance(port, int)


def test_invalid_port_numbers():
    """Test rejection of invalid port numbers."""
    invalid_ports = [0, -1, 65536, 100000]
    
    for port in invalid_ports:
        is_valid = isinstance(port, int) and 1 <= port <= 65535
        assert not is_valid, f"Invalid port accepted: {port}"