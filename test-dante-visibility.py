#!/usr/bin/env python3
"""
Test script to verify Dante device visibility using network-audio-controller
This properly tests if our media-bridge device is discoverable on the Dante network
"""

import sys
import time
from zeroconf import ServiceBrowser, Zeroconf
import socket

class DanteListener:
    def __init__(self):
        self.devices = {}
        
    def add_service(self, zeroconf, type, name):
        info = zeroconf.get_service_info(type, name)
        if info:
            device_name = name.split('.')[0]
            if info.addresses:
                ip = socket.inet_ntoa(info.addresses[0])
                self.devices[device_name] = {
                    'ip': ip,
                    'port': info.port,
                    'type': type
                }
                print(f"✓ Found Dante device: {device_name} at {ip}:{info.port}")
                if "media-bridge" in device_name.lower() or "10.77.8.122" in ip:
                    print(f"  >>> THIS IS OUR DEVICE! <<<")
            
    def remove_service(self, zeroconf, type, name):
        pass
        
    def update_service(self, zeroconf, type, name):
        pass

def test_dante_visibility(target_ip="10.77.8.122"):
    print("=" * 60)
    print("Dante Device Discovery Test")
    print("=" * 60)
    print(f"Looking for device at IP: {target_ip}")
    print("Scanning for Dante devices on network...")
    print()
    
    zeroconf = Zeroconf()
    listener = DanteListener()
    
    # Dante uses these service types
    dante_services = [
        "_netaudio-arc._udp.local.",  # Audio Receiver Control
        "_netaudio-cmc._udp.local.",  # Connection Management Control  
        "_netaudio-dbc._udp.local.",  # Device Browser Control
        "_netaudio-acc._udp.local.",  # Audio Controller Control
    ]
    
    browsers = []
    for service in dante_services:
        print(f"Scanning for {service}...")
        browser = ServiceBrowser(zeroconf, service, listener)
        browsers.append(browser)
    
    # Wait for discovery
    print("\nWaiting 10 seconds for discovery...")
    for i in range(10):
        time.sleep(1)
        print(f"  {i+1}...", end="", flush=True)
    print()
    
    print("\n" + "=" * 60)
    print("RESULTS:")
    print("=" * 60)
    
    found_target = False
    if listener.devices:
        print(f"Found {len(listener.devices)} Dante device(s):")
        for name, info in listener.devices.items():
            print(f"  - {name}: {info['ip']}:{info['port']} ({info['type']})")
            if target_ip in info['ip'] or "media-bridge" in name.lower():
                found_target = True
                print(f"    ^^^ TARGET DEVICE FOUND! ^^^")
    else:
        print("❌ NO Dante devices found on network!")
    
    print()
    
    # Also check direct UDP ports
    print("Checking direct UDP discovery ports on target...")
    import subprocess
    try:
        # Use netcat to check if ports are open
        for port in [8700, 8701, 8800, 8801, 4455]:
            result = subprocess.run(
                ["nc", "-zvu", target_ip, str(port)], 
                capture_output=True, 
                timeout=2
            )
            if result.returncode == 0:
                print(f"  ✓ Port {port} is OPEN on {target_ip}")
            else:
                print(f"  ✗ Port {port} is CLOSED on {target_ip}")
    except Exception as e:
        print(f"  Could not check ports: {e}")
    
    print("\n" + "=" * 60)
    if found_target:
        print("✅ SUCCESS: media-bridge device IS VISIBLE in Dante network!")
    else:
        print("❌ FAILURE: media-bridge device NOT VISIBLE in Dante network!")
        print("\nPossible issues:")
        print("  1. Inferno not advertising via mDNS")
        print("  2. Avahi daemon not running on device")
        print("  3. Firewall blocking mDNS (port 5353)")
        print("  4. Device not on same network/VLAN")
    print("=" * 60)
    
    zeroconf.close()
    
    return found_target

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "10.77.8.122"
    success = test_dante_visibility(target)
    sys.exit(0 if success else 1)