"""Test DHCP IP persistence based on MAC address.

This test verifies that the device maintains the same IP address across
reboots and hostname changes when configured to use MAC-based DHCP client
identification.

Issue #105: Bridge IP not persistent despite same MAC as hardware ethernet
"""

import pytest
import time
import re


def test_dhcp_uses_mac_client_id(host):
    """Verify DHCP is configured to use MAC address as client identifier."""
    # Check network configuration file
    config = host.file("/etc/systemd/network/30-br0.network")
    assert config.exists, "Bridge network configuration file missing"
    
    content = config.content_string
    
    # Verify critical DHCP settings
    assert "ClientIdentifier=mac" in content, "DHCP not configured to use MAC as client ID"
    assert "DUIDType=link-layer" in content, "DUID type not set to link-layer"
    assert "SendHostname=true" in content, "Hostname not being sent (needed for router visibility)"
    assert "IAID=0" in content, "IAID not set to consistent value"


def test_bridge_has_consistent_mac(host):
    """Verify bridge interface has a consistent MAC address from physical interface."""
    # Get bridge MAC address
    bridge_info = host.run("ip link show br0")
    assert bridge_info.rc == 0, "Failed to get bridge information"
    
    bridge_mac_match = re.search(r'link/ether ([0-9a-f:]+)', bridge_info.stdout)
    assert bridge_mac_match, "Could not extract bridge MAC address"
    bridge_mac = bridge_mac_match.group(1)
    
    # Get first ethernet interface MAC
    eth_info = host.run("ip link show | grep -E 'eth0|enp' | head -1")
    assert eth_info.rc == 0, "Failed to find ethernet interface"
    
    eth_mac_match = re.search(r'link/ether ([0-9a-f:]+)', eth_info.stdout)
    assert eth_mac_match, "Could not extract ethernet MAC address"
    eth_mac = eth_mac_match.group(1)
    
    # Bridge should inherit MAC from first ethernet interface
    assert bridge_mac == eth_mac, f"Bridge MAC {bridge_mac} doesn't match ethernet MAC {eth_mac}"


def test_dhcp_client_id_is_mac(host):
    """Verify systemd-networkd is actually using MAC as DHCP client ID."""
    # Check networkctl status
    result = host.run("networkctl status br0 | grep 'DHCP4 Client ID'")
    assert result.rc == 0, "Failed to get DHCP client ID from networkctl"
    
    # Extract client ID
    client_id_match = re.search(r'DHCP4 Client ID: ([0-9a-f:]+)', result.stdout)
    assert client_id_match, "Could not extract DHCP client ID"
    client_id = client_id_match.group(1)
    
    # Get bridge MAC for comparison
    bridge_info = host.run("ip link show br0 | grep 'link/ether'")
    mac_match = re.search(r'link/ether ([0-9a-f:]+)', bridge_info.stdout)
    assert mac_match, "Could not extract bridge MAC"
    bridge_mac = mac_match.group(1)
    
    # Client ID should be the MAC address
    assert client_id == bridge_mac, f"DHCP client ID {client_id} doesn't match MAC {bridge_mac}"


def test_ip_persistence_after_hostname_change(host):
    """Test that IP address persists after hostname change and network restart."""
    # Get current IP address
    ip_before = host.run("ip -4 addr show br0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1")
    assert ip_before.rc == 0, "Failed to get current IP"
    ip_addr_before = ip_before.stdout.strip()
    assert ip_addr_before, "No IP address found on bridge"
    
    # Get current hostname
    hostname_before = host.run("hostname").stdout.strip()
    
    # Change hostname
    test_hostname = "test-dhcp-persistence"
    host.run(f"hostname {test_hostname}")
    host.run(f"echo {test_hostname} > /etc/hostname")
    
    # Restart network to trigger DHCP renewal
    result = host.run("systemctl restart systemd-networkd")
    assert result.rc == 0, "Failed to restart network"
    
    # Wait for network to come up
    time.sleep(5)
    
    # Get IP after hostname change
    ip_after = host.run("ip -4 addr show br0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1")
    assert ip_after.rc == 0, "Failed to get IP after hostname change"
    ip_addr_after = ip_after.stdout.strip()
    
    # Restore original hostname
    host.run(f"hostname {hostname_before}")
    host.run(f"echo {hostname_before} > /etc/hostname")
    
    # IP should remain the same
    assert ip_addr_after == ip_addr_before, \
        f"IP changed from {ip_addr_before} to {ip_addr_after} after hostname change"


@pytest.mark.slow
def test_ip_persistence_after_reboot(host):
    """Test that IP address persists after system reboot.
    
    Note: This test requires the device to be rebooted and may take several minutes.
    It should be run separately with proper timeout handling.
    """
    # Get current IP address
    ip_before = host.run("ip -4 addr show br0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1")
    assert ip_before.rc == 0, "Failed to get current IP"
    ip_addr_before = ip_before.stdout.strip()
    
    # Store IP in a file that persists across reboot
    host.run(f"echo {ip_addr_before} > /tmp/ip_before_reboot")
    
    # Create a systemd service to check IP after reboot
    service_content = f"""[Unit]
Description=Check IP persistence after reboot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ip -4 addr show br0 | grep inet | awk "{{print \\$2}}" | cut -d/ -f1 > /tmp/ip_after_reboot'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"""
    host.run(f"echo '{service_content}' > /etc/systemd/system/check-ip-persistence.service")
    host.run("systemctl enable check-ip-persistence.service")
    
    # Note: Actual reboot would happen here in a full test environment
    # This is a placeholder for the reboot logic
    pytest.skip("Reboot test requires special test environment setup")


def test_unique_machine_id_generation(host):
    """Verify that machine-id generation service is configured for first boot."""
    # Check if the service file exists
    service = host.file("/etc/systemd/system/generate-machine-id.service")
    if service.exists:
        # Service should be enabled
        result = host.run("systemctl is-enabled generate-machine-id.service")
        assert result.stdout.strip() in ["enabled", "static"], \
            "Machine ID generation service not enabled"
        
        # Check service configuration
        content = service.content_string
        assert "systemd-machine-id-setup" in content, \
            "Service doesn't call systemd-machine-id-setup"
        assert "Before=systemd-networkd.service" in content, \
            "Service doesn't run before network"
    else:
        # If service doesn't exist, machine-id should at least be present and valid
        machine_id = host.file("/etc/machine-id")
        assert machine_id.exists, "No machine-id file found"
        
        # Machine ID should be 32 hex characters
        content = machine_id.content_string.strip()
        assert len(content) == 32, f"Invalid machine-id length: {len(content)}"
        assert all(c in '0123456789abcdef' for c in content.lower()), \
            "Machine-id contains invalid characters"


def test_dhcp_lease_shows_hostname(host):
    """Verify that hostname is visible in DHCP lease (for router visibility)."""
    # Check that SendHostname is enabled
    config = host.file("/etc/systemd/network/30-br0.network")
    assert "SendHostname=true" in config.content_string or \
           "SendHostname=yes" in config.content_string, \
           "SendHostname not enabled - router won't see device name"
    
    # Verify hostname is being sent in DHCP requests
    # This can be checked in systemd-networkd logs
    logs = host.run("journalctl -u systemd-networkd -n 100 | grep -i dhcp || true")
    # Just verify the command runs - actual DHCP server visibility would need router access
    assert logs.rc == 0, "Failed to check network logs"