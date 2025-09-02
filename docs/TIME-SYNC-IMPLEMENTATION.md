# Media Bridge Time Synchronization Implementation

## Overview

This document describes the implementation of high-precision time synchronization in the Media Bridge USB system. The implementation provides sub-microsecond accuracy when properly configured with PTP, or millisecond accuracy with NTP as a fallback.

## Implementation Details

### 1. New Build Module

A new build module `scripts/build-modules/15-time-sync.sh` was created to handle time synchronization setup during USB creation:

- Installs LinuxPTP for PTP support
- Installs chrony for NTP support
- Configures ptp4l and phc2sys daemons
- Creates systemd services for automatic startup
- Includes a verification utility `check_clocks`

### 2. Main Build Script Integration

The main build script `scripts/build-ndi-usb-modular.sh` was updated to include the new time sync module in the build process.

### 3. NDI Service Integration

The NDI capture service script `scripts/build-modules/09-ndi-capture-service.sh` was modified to check time synchronization status before starting the NDI Capture application.

### 4. Test Script

A test script `scripts/test-time-sync.sh` was created to validate time synchronization on built systems.

## Configuration Files

### PTP Configuration

The implementation creates configuration files for ptp4l and phc2sys:

- `/etc/linuxptp/gPTP.cfg` - PTP slave configuration (default)
- `/etc/linuxptp/master.cfg` - PTP master configuration (for grandmaster clocks)
- `/etc/linuxptp/phc2sys.conf` - PHC to system clock synchronization

By default, the system is configured to act as a PTP slave, synchronizing to any available master clock on the network. For systems that should act as a master (grandmaster clock), the configuration can be changed by modifying the ptp4l systemd service to use the master configuration file.

### NTP Configuration

Chrony is configured as a fallback:

- `/etc/chrony/chrony.conf` - NTP client configuration

## Systemd Services

The implementation creates systemd services for automatic startup:

- `ptp4l.service` - PTP master/slave daemon
- `phc2sys.service` - Hardware clock synchronization
- `chrony.service` - NTP client

## Verification

### Built-in Verification

The NDI service now checks time synchronization before starting:

1. First tries `check_clocks` utility for PTP verification
2. Falls back to `chronyc` for NTP verification
3. Continues with warning if neither can verify sync

### Manual Verification

Users can verify time synchronization with:

```bash
# Check if services are running
systemctl status ptp4l
systemctl status phc2sys
systemctl status chrony

# Verify clock synchronization
/usr/local/bin/check_clocks

# Check detailed PTP status
journalctl -u ptp4l -f
journalctl -u phc2sys -f

# Check NTP status
chronyc tracking
chronyc sources
```

## Network Requirements

### For Optimal PTP Performance

- Connect to a network with a PTP grandmaster clock
- Use switches that support PTP hardware timestamping
- Ensure all devices are on the same network segment

### NTP Fallback

If PTP is not available, the system will fall back to NTP synchronization with a reliable time server.

## Benefits

This implementation provides:

1. **Sub-microsecond accuracy** with PTP when properly configured
2. **Millisecond accuracy** with NTP as fallback
3. **Automatic startup** of synchronization services
4. **Verification before NDI start** for optimal frame sync
5. **Comprehensive monitoring** capabilities

## Testing

The `scripts/test-time-sync.sh` script can be used to validate the implementation:

```bash
# Test on a built USB system
./scripts/test-time-sync.sh

# Simulate testing without a built system
./scripts/test-time-sync.sh --simulate
```

## Documentation

Updated documentation includes:

1. `docs/USB-BUILD.md` - Added Time Synchronization section
2. `README.md` - Added time sync feature to USB Appliance Features
3. This document - Detailed implementation information

## Future Improvements

Potential future enhancements:

1. Configuration options for different PTP network scenarios
2. Enhanced monitoring and alerting for synchronization issues
3. Automatic switching between PTP and NTP based on network conditions
4. Integration with NDI SDK's built-in timecode features
