#!/bin/bash
# Network functionality test suite
# Tests network configuration, bridge, DHCP, mDNS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/assertions.sh"
source "${SCRIPT_DIR}/../lib/box_control.sh"

# Test configuration
TEST_NAME="Network Test Suite"

# Initialize test logs
setup_test_logs

log_test "Starting $TEST_NAME"
log_info "Target box: $TEST_BOX_IP"

# Check box connectivity
if ! box_ping; then
    log_error "Box at $TEST_BOX_IP is not reachable"
    exit 1
fi

# Test 1: Network interface configuration
log_test "Test 1: Network interface configuration"

# Check bridge interface
bridge_info=$(box_ssh "ip addr show br0 2>/dev/null")
if [ -n "$bridge_info" ]; then
    record_test "Bridge Interface" "PASS" "br0 interface exists"
    
    # Extract IP address
    ip_addr=$(echo "$bridge_info" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ -n "$ip_addr" ]; then
        record_test "IP Address" "PASS" "IP: $ip_addr"
    else
        record_test "IP Address" "FAIL" "No IP address assigned"
    fi
else
    record_test "Bridge Interface" "FAIL" "br0 interface not found"
fi

# Check physical interfaces in bridge
bridge_members=$(box_ssh "bridge link show 2>/dev/null | grep 'master br0' | awk '{print \$2}'")
if [ -n "$bridge_members" ]; then
    record_test "Bridge Members" "PASS" "Members: $(echo $bridge_members | tr '\n' ' ')"
else
    record_test "Bridge Members" "WARN" "No interfaces in bridge"
fi

# Test 2: DHCP client status
log_test "Test 2: DHCP client status"

dhcp_status=$(box_ssh "systemctl is-active systemd-networkd" | tr -d '\n')
if [ "$dhcp_status" = "active" ]; then
    record_test "Network Service" "PASS" "systemd-networkd active"
    
    # Check for DHCP lease
    dhcp_lease=$(box_ssh "networkctl status br0 2>/dev/null | grep -i dhcp")
    if [ -n "$dhcp_lease" ]; then
        record_test "DHCP Configuration" "PASS"
    else
        record_test "DHCP Configuration" "INFO" "Static IP or no DHCP info"
    fi
else
    record_test "Network Service" "FAIL" "systemd-networkd not active"
fi

# Test 3: DNS resolution
log_test "Test 3: DNS resolution"

# Test DNS resolution
dns_test=$(box_ssh "nslookup google.com 2>/dev/null | grep -c 'Address:' || echo 0")
# Convert to integer, removing any whitespace
dns_test=$(echo "$dns_test" | tr -d '[:space:]')
if [ -z "$dns_test" ]; then
    dns_test=0
fi
if [ "$dns_test" -gt 1 ]; then
    record_test "DNS Resolution" "PASS" "DNS working"
else
    record_test "DNS Resolution" "FAIL" "DNS not working"
fi

# Check resolv.conf
nameservers=$(box_ssh "grep nameserver /etc/resolv.conf 2>/dev/null | head -3")
if [ -n "$nameservers" ]; then
    log_info "Nameservers configured:"
    echo "$nameservers"
    record_test "DNS Configuration" "PASS"
else
    record_test "DNS Configuration" "FAIL" "No nameservers configured"
fi

# Test 4: mDNS/Avahi service
log_test "Test 4: mDNS/Avahi service"

avahi_status=$(box_ssh "systemctl is-active avahi-daemon" | tr -d '\n')
if [ "$avahi_status" = "active" ]; then
    record_test "Avahi Service" "PASS"
    
    # Check mDNS hostname
    hostname=$(box_ssh "hostname")
    mdns_name="${hostname}.local"
    log_info "mDNS name should be: $mdns_name"
    
    # Check if avahi is advertising
    avahi_browse=$(box_ssh "avahi-browse -a -t -r 2>/dev/null | grep -c '_http._tcp' || echo 0")
    # Convert to integer, removing any whitespace
    avahi_browse=$(echo "$avahi_browse" | tr -d '[:space:]')
    if [ -z "$avahi_browse" ]; then
        avahi_browse=0
    fi
    if [ "$avahi_browse" -gt 0 ]; then
        record_test "mDNS Advertisement" "PASS" "Services advertised via mDNS"
    else
        record_test "mDNS Advertisement" "WARN" "No services advertised"
    fi
else
    record_test "Avahi Service" "FAIL" "Avahi not running"
fi

# Test 5: Network connectivity
log_test "Test 5: Network connectivity"

# Test local network
ping_local=$(box_ssh "ping -c 1 -W 2 $TEST_BOX_IP &>/dev/null && echo 'ok' || echo 'fail'")
if [ "$ping_local" = "ok" ]; then
    record_test "Local Network" "PASS" "Can ping own IP"
else
    record_test "Local Network" "FAIL" "Cannot ping own IP"
fi

# Test gateway
gateway=$(box_ssh "ip route | grep default | awk '{print \$3}' | head -1")
if [ -n "$gateway" ]; then
    ping_gw=$(box_ssh "ping -c 1 -W 2 $gateway &>/dev/null && echo 'ok' || echo 'fail'")
    if [ "$ping_gw" = "ok" ]; then
        record_test "Gateway Connectivity" "PASS" "Gateway: $gateway"
    else
        record_test "Gateway Connectivity" "FAIL" "Cannot reach gateway: $gateway"
    fi
else
    record_test "Gateway Connectivity" "FAIL" "No default gateway"
fi

# Test internet
ping_internet=$(box_ssh "ping -c 1 -W 2 8.8.8.8 &>/dev/null && echo 'ok' || echo 'fail'")
if [ "$ping_internet" = "ok" ]; then
    record_test "Internet Connectivity" "PASS"
else
    record_test "Internet Connectivity" "WARN" "No internet access"
fi

# Test 6: Firewall status
log_test "Test 6: Firewall configuration"

# Check iptables rules
iptables_count=$(box_ssh "iptables -L -n 2>/dev/null | grep -c 'Chain' || echo 0")
# Convert to integer, removing any whitespace
iptables_count=$(echo "$iptables_count" | tr -d '[:space:]')
if [ -z "$iptables_count" ]; then
    iptables_count=0
fi
if [ "$iptables_count" -gt 0 ]; then
    # Check if firewall is restrictive
    policy=$(box_ssh "iptables -L INPUT -n 2>/dev/null | grep 'Chain INPUT' | grep -o '(policy [A-Z]*)'")
    if echo "$policy" | grep -q "ACCEPT"; then
        record_test "Firewall Status" "PASS" "Firewall configured (policy: ACCEPT)"
    else
        record_test "Firewall Status" "INFO" "Firewall configured: $policy"
    fi
else
    record_test "Firewall Status" "INFO" "No firewall rules configured"
fi

# Test 7: Network performance
log_test "Test 7: Network interface speed"

# Check interface speed
interface_speed=$(box_ssh "ethtool eth0 2>/dev/null | grep 'Speed:' | awk '{print \$2}'")
if [ -n "$interface_speed" ]; then
    record_test "Interface Speed" "PASS" "Speed: $interface_speed"
else
    # Try another interface
    interface_speed=$(box_ssh "ethtool enp1s0 2>/dev/null | grep 'Speed:' | awk '{print \$2}'")
    if [ -n "$interface_speed" ]; then
        record_test "Interface Speed" "PASS" "Speed: $interface_speed"
    else
        record_test "Interface Speed" "INFO" "Could not determine interface speed"
    fi
fi

# Test 8: NDI network discovery
log_test "Test 8: NDI network discovery"

# Check if NDI discovery port is open
ndi_port_5353=$(box_ssh "netstat -uln 2>/dev/null | grep -c ':5353' || echo 0")
ndi_port_5960=$(box_ssh "netstat -tln 2>/dev/null | grep -c ':5960' || echo 0")

if [ "$ndi_port_5353" -gt 0 ]; then
    record_test "NDI mDNS Port (5353)" "PASS" "Port open for NDI discovery"
else
    record_test "NDI mDNS Port (5353)" "WARN" "NDI discovery port not open"
fi

if [ "$ndi_port_5960" -gt 0 ]; then
    record_test "NDI TCP Port (5960)" "PASS" "NDI TCP port open"
else
    record_test "NDI TCP Port (5960)" "INFO" "NDI TCP port not open"
fi

# Collect diagnostic information
log_info "Collecting network diagnostic information..."

# Get routing table
routing_table=$(box_ssh "ip route")
log_output "Routing Table" "$routing_table"

# Get network interfaces
interfaces=$(box_ssh "ip -br addr")
log_output "Network Interfaces" "$interfaces"

# Print test summary
print_test_summary

if [ $TEST_FAILED -eq 0 ]; then
    log_info "✅ All network tests passed!"
    exit 0
else
    log_error "❌ $TEST_FAILED network tests failed"
    exit 1
fi