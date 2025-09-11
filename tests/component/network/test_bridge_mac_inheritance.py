"""
Test that bridge properly inherits MAC address from first ethernet interface.
This is critical for DHCP IP persistence.
"""
import re
import time


def test_bridge_inherits_mac_from_first_ethernet(host):
    """Verify bridge always inherits MAC from first ethernet interface."""
    # Get first ethernet interface and its MAC
    eth_list = host.run("ip link show | grep -E '^[0-9]+: (eth|enp|eno)' | head -1")
    assert eth_list.rc == 0, "No ethernet interfaces found"
    
    # Extract interface name from "2: eth0: <...>" format
    iface_match = re.search(r'^\d+: ([^:]+):', eth_list.stdout)
    assert iface_match, f"Could not parse interface from: {eth_list.stdout}"
    first_eth = iface_match.group(1)
    
    # Get MAC of first ethernet interface
    eth_info = host.run(f"ip link show {first_eth}")
    assert eth_info.rc == 0, f"Failed to get info for {first_eth}"
    
    eth_mac_match = re.search(r'link/ether ([0-9a-f:]+)', eth_info.stdout)
    assert eth_mac_match, f"Could not extract MAC from {first_eth}"
    eth_mac = eth_mac_match.group(1)
    
    # Get bridge MAC
    br_info = host.run("ip link show br0")
    assert br_info.rc == 0, "Failed to get bridge info"
    
    br_mac_match = re.search(r'link/ether ([0-9a-f:]+)', br_info.stdout)
    assert br_mac_match, "Could not extract bridge MAC"
    br_mac = br_mac_match.group(1)
    
    # Bridge MUST have same MAC as first ethernet
    assert br_mac == eth_mac, \
        f"Bridge MAC {br_mac} doesn't match first ethernet {first_eth} MAC {eth_mac}"


def test_bridge_mac_survives_network_restart(host):
    """Verify bridge MAC stays consistent after network restart."""
    # Get current bridge MAC
    before_info = host.run("ip link show br0 | grep -o 'link/ether [0-9a-f:]*' | cut -d' ' -f2")
    assert before_info.rc == 0, "Failed to get bridge MAC"
    mac_before = before_info.stdout.strip()
    
    # Get first ethernet MAC for reference
    eth_info = host.run("ip link show eth0 2>/dev/null | grep -o 'link/ether [0-9a-f:]*' | cut -d' ' -f2 || ip link show enp1s0 | grep -o 'link/ether [0-9a-f:]*' | cut -d' ' -f2")
    assert eth_info.rc == 0, "Failed to get ethernet MAC"
    eth_mac = eth_info.stdout.strip()
    
    # Restart networking
    restart = host.run("systemctl restart systemd-networkd")
    assert restart.rc == 0, "Failed to restart network"
    
    # Wait for network to stabilize
    time.sleep(3)
    
    # Check bridge MAC after restart
    after_info = host.run("ip link show br0 | grep -o 'link/ether [0-9a-f:]*' | cut -d' ' -f2")
    assert after_info.rc == 0, "Failed to get bridge MAC after restart"
    mac_after = after_info.stdout.strip()
    
    # Verify MACs
    assert mac_after == mac_before, \
        f"Bridge MAC changed after restart: {mac_before} -> {mac_after}"
    assert mac_after == eth_mac, \
        f"Bridge MAC {mac_after} doesn't match ethernet MAC {eth_mac}"


def test_no_macaddress_in_netdev_file(host):
    """Verify bridge netdev file doesn't have invalid MACAddress=none."""
    netdev = host.file("/etc/systemd/network/10-br0.netdev")
    assert netdev.exists, "Bridge netdev file missing"
    
    content = netdev.content_string
    assert "MACAddress=none" not in content, \
        "Invalid 'MACAddress=none' found in netdev file"
    
    # MACAddress line should either be absent or have a valid MAC
    if "MACAddress=" in content:
        mac_match = re.search(r'MACAddress=([0-9a-fA-F:]+)', content)
        assert mac_match, "MACAddress line exists but has invalid format"
        mac = mac_match.group(1)
        # Validate MAC format
        assert re.match(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$', mac), \
            f"Invalid MAC address format: {mac}"


def test_bridge_uses_lowest_mac_when_multiple_interfaces(host):
    """Verify bridge uses lowest MAC when multiple interfaces are enslaved."""
    # Get all interfaces in bridge
    bridge_ports = host.run("bridge link show | grep 'master br0' | cut -d: -f2 | cut -d' ' -f2")
    assert bridge_ports.rc == 0, "Failed to get bridge ports"
    
    ports = bridge_ports.stdout.strip().split('\n')
    if len(ports) < 2:
        # Skip test if only one interface
        return
    
    # Get all MACs
    macs = []
    for port in ports:
        if port:
            mac_info = host.run(f"ip link show {port} | grep -o 'link/ether [0-9a-f:]*' | cut -d' ' -f2")
            if mac_info.rc == 0 and mac_info.stdout.strip():
                macs.append(mac_info.stdout.strip())
    
    if len(macs) < 2:
        return  # Not enough interfaces with MACs
    
    # Bridge should use the lowest MAC
    lowest_mac = min(macs)
    
    br_mac_info = host.run("ip link show br0 | grep -o 'link/ether [0-9a-f:]*' | cut -d' ' -f2")
    assert br_mac_info.rc == 0, "Failed to get bridge MAC"
    br_mac = br_mac_info.stdout.strip()
    
    assert br_mac == lowest_mac, \
        f"Bridge MAC {br_mac} is not the lowest MAC {lowest_mac} from ports: {macs}"


class TestBridgePersistence:
    """Test that bridge configuration survives reboots."""
    
    def test_bridge_survives_reboot(self, host):
        """Test that bridge configuration is persistent after reboot."""
        # Check bridge config files exist
        bridge_netdev = host.file("/etc/systemd/network/10-br0.netdev")
        assert bridge_netdev.exists, "Bridge netdev configuration should exist"
        
        bridge_network = host.file("/etc/systemd/network/30-br0.network")
        assert bridge_network.exists, "Bridge network configuration should exist"
        
        # Check services are enabled
        fix_mac_service = host.service("media-bridge-fix-mac")
        assert fix_mac_service.is_enabled, "MAC fix service should be enabled for boot"
    
    def test_dhcp_lease_persistence_directory(self, host):
        """Test that systemd-networkd has a directory to persist DHCP leases."""
        # Check persistent storage directory exists
        lease_dir = host.file("/var/lib/systemd/network")
        assert lease_dir.exists, "Persistent DHCP lease directory should exist"
        assert lease_dir.is_directory, "Should be a directory"
        
        # Check ownership
        assert lease_dir.user == "systemd-network", "Directory should be owned by systemd-network"
        assert lease_dir.group == "systemd-network", "Directory should be owned by systemd-network group"
        
        # Check systemd-networkd is configured to use persistent storage
        override = host.file("/etc/systemd/system/systemd-networkd.service.d/lease-persistence.conf")
        assert override.exists, "systemd-networkd override for lease persistence should exist"
        assert "StateDirectory=systemd/network" in override.content_string, \
            "systemd-networkd should be configured to use persistent StateDirectory"
    
    def test_dhcp_client_id_uses_mac(self, host):
        """Test that DHCP client ID is configured to use MAC address."""
        # Check bridge network configuration
        config = host.file("/etc/systemd/network/30-br0.network")
        assert config.exists, "Bridge network config should exist"
        
        # Check for ClientIdentifier=mac setting
        assert "ClientIdentifier=mac" in config.content_string, \
            "DHCP should be configured to use MAC as client ID"