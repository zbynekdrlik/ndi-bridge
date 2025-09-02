# PTP Version Conflict Resolution

## The Problem

The NDI Bridge needs to support two incompatible PTP protocols simultaneously:

1. **NDI Streaming**: Uses PTPv2 (IEEE 1588-2008) on UDP ports 319-320
2. **Dante Audio**: Uses PTPv1 (IEEE 1588-2002) on UDP ports 319-320

**Both protocols use the SAME multicast addresses and ports!**
- PTPv1: 224.0.1.129 (ports 319-320)
- PTPv2: 224.0.1.129 (ports 319-320)

This creates an impossible situation where two different PTP daemons would fight for control of the same network resources.

## Current Implementation Issues

### What Happens Now

1. **Without Dante Enabled**:
   - `ptp4l` (LinuxPTP) runs for NDI PTPv2
   - `phc2sys` syncs system clock to PTP
   - NDI streams have proper time sync
   - Everything works fine

2. **With Dante Enabled**:
   - `statime` (Inferno fork) starts for Dante PTPv1
   - `statime.service` has `Conflicts=ptp4l.service`
   - This STOPS ptp4l completely
   - **NDI loses PTP sync entirely!**
   - Dante gets PTP sync but NDI is broken

### The Core Conflict

```
Port 319/320 UDP can only be bound by ONE process:
- ptp4l binds it → NDI works, Dante broken
- statime binds it → Dante works, NDI broken
- Both try to bind → First one wins, second fails
```

## Why This Is Critical

### NDI Impact
- NDI uses PTPv2 for frame-accurate sync
- Without PTP, NDI falls back to NTP (millisecond precision)
- This causes:
  - Frame drops
  - Audio/video drift
  - Reduced stream quality
  - Sync issues with multiple streams

### Dante Impact
- Dante REQUIRES PTPv1 for audio clock sync
- Without PTP, Dante cannot function at all
- No fallback mechanism exists

## Possible Solutions

### Option 1: Separate Network Interfaces (RECOMMENDED)
```
eth0/br0 → NDI PTPv2 (ptp4l)
eth1     → Dante PTPv1 (statime)
```

**Pros:**
- Both PTP daemons can run simultaneously
- No port conflicts
- Full functionality for both systems

**Cons:**
- Requires second network interface
- May need VLAN configuration

**Implementation:**
```bash
# Configure statime for eth1
DANTE_INTERFACE=eth1

# Configure ptp4l for br0
ptp4l -i br0 ...
```

### Option 2: Time-Division Multiplexing
Alternate between PTP daemons based on active use:

```bash
if dante_audio_active; then
    systemctl stop ptp4l
    systemctl start statime
else
    systemctl stop statime
    systemctl start ptp4l
fi
```

**Pros:**
- Works with single interface
- No hardware changes

**Cons:**
- Cannot use NDI and Dante simultaneously
- Switching causes sync loss
- Complex state management

### Option 3: PTP Proxy/Translation Layer
Create a proxy that translates between PTPv1 and PTPv2:

```
Network → PTP Proxy → statime (PTPv1)
                   ↘→ ptp4l (PTPv2)
```

**Pros:**
- Single network interface
- Both protocols supported

**Cons:**
- Complex to implement
- Adds latency
- May introduce timing errors

### Option 4: Virtual Interfaces with Netfilter
Use iptables/nftables to redirect PTP traffic:

```bash
# Create virtual interface for Dante
ip link add dante0 type dummy

# Redirect PTPv1 traffic to virtual interface
iptables -t nat -A PREROUTING -p udp --dport 319 \
    -m u32 --u32 "28&0xFF=0x00" -j DNAT --to-destination dante0

# Redirect PTPv2 traffic to main interface  
iptables -t nat -A PREROUTING -p udp --dport 319 \
    -m u32 --u32 "28&0xFF=0x02" -j DNAT --to-destination br0
```

**Pros:**
- Single physical interface
- Protocol-aware routing

**Cons:**
- Complex iptables rules
- May not work with multicast
- Kernel-dependent behavior

## Current Workaround Implementation

The current implementation uses a **mutual exclusion** approach:

### 1. Service Conflicts
```ini
# In statime.service
Conflicts=ptp4l.service phc2sys.service
```

### 2. Coordination Script
```bash
# In time-sync-coordinator
is_dante_mode() {
    if systemctl is-active statime >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

manage_services() {
    if is_dante_mode; then
        # Stop NDI PTP to avoid conflicts
        systemctl stop ptp4l
        systemctl stop phc2sys
        return
    fi
    # ... continue with normal PTP
}
```

### 3. Priority System
- Dante takes priority when enabled
- NDI falls back to NTP when Dante active
- User must choose: Dante OR precise NDI sync

## Impact Analysis

### When Dante is Active:
| Feature | Status | Impact |
|---------|--------|--------|
| Dante Audio | ✅ Working | Full 96kHz audio with PTPv1 sync |
| NDI Streaming | ⚠️ Degraded | Falls back to NTP (ms precision) |
| NDI Frame Sync | ❌ Lost | No frame-accurate sync |
| Multiple NDI Streams | ⚠️ Risk | May drift apart over time |

### When Dante is Inactive:
| Feature | Status | Impact |
|---------|--------|--------|
| Dante Audio | ❌ Disabled | No Dante functionality |
| NDI Streaming | ✅ Working | Full PTPv2 sync |
| NDI Frame Sync | ✅ Working | Microsecond precision |
| Multiple NDI Streams | ✅ Working | Perfect sync maintained |

## Recommended Production Deployment

### For Dante-Primary Systems:
```bash
# Disable NDI PTP permanently
systemctl disable ptp4l
systemctl disable phc2sys

# Enable Dante PTP
systemctl enable statime
systemctl enable dante-bridge
```

### For NDI-Primary Systems:
```bash
# Keep Dante disabled
systemctl disable statime
systemctl disable dante-bridge

# NDI PTP runs normally
systemctl enable ptp4l
systemctl enable phc2sys
```

### For Dual-Use Systems:
**Use separate network interfaces:**
1. Add USB-to-Ethernet adapter for Dante
2. Configure Dante on separate interface
3. Keep NDI on main bridge interface

## Future Improvements

### Short Term:
1. Add user-selectable mode in web interface
2. Implement automatic switching based on active streams
3. Add warning when enabling Dante about NDI impact

### Long Term:
1. Implement PTP proxy for protocol translation
2. Add second Ethernet port in hardware
3. Use SR-IOV for virtual network functions

## Configuration Examples

### Separate Interfaces (Best Solution):
```bash
# /etc/ndi-bridge/dante.conf
DANTE_INTERFACE=eth1  # Dedicated Dante interface

# /etc/linuxptp/ptp4l.conf
[global]
domainNumber 0
[br0]  # NDI on bridge interface
```

### Mode Selection Script:
```bash
#!/bin/bash
# /usr/local/bin/ndi-bridge-set-mode

case "$1" in
    dante)
        systemctl stop ptp4l phc2sys
        systemctl start statime dante-bridge
        echo "Dante mode active (NDI PTP disabled)"
        ;;
    ndi)
        systemctl stop statime dante-bridge
        systemctl start ptp4l phc2sys
        echo "NDI mode active (Dante disabled)"
        ;;
    *)
        echo "Usage: $0 {dante|ndi}"
        exit 1
        ;;
esac
```

## User Guidance

### Decision Tree:
```
Do you need Dante audio?
├── Yes → Do you also need precise NDI sync?
│   ├── Yes → Add second network interface
│   └── No → Use Dante mode (NDI with NTP)
└── No → Use standard NDI mode with PTPv2
```

### Warning Messages:
When enabling Dante, show:
```
⚠️ WARNING: Enabling Dante will disable PTPv2 for NDI
- NDI streams will use NTP (lower precision)
- Frame-accurate sync will be lost
- Consider using separate network interface for Dante

Continue? [y/N]
```

## Conclusion

The PTPv1/PTPv2 conflict is a fundamental protocol incompatibility. The current implementation prioritizes Dante when enabled, sacrificing NDI's precise timing. For production systems requiring both, separate network interfaces are the only complete solution.

**Current Status**: Dante and NDI PTP are mutually exclusive on the same interface. When Dante is enabled, NDI loses microsecond-precision sync and falls back to NTP.