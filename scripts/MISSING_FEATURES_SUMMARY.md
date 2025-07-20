# Missing Features Summary: Modular vs Monolithic Build Scripts

## Executive Summary

The modular build script (v1.3.0) successfully builds a bootable USB but is missing critical power-failure resistance features present in the monolithic version (v1.1.3).

## Critical Missing Features

### 1. **Read-Only Root Filesystem** ⚠️ CRITICAL
- **Monolithic**: Root mounted as read-only (`ro,noatime,errors=remount-ro`)
- **Modular**: Root remains read-write (vulnerable to corruption)
- **Impact**: Power failures can corrupt the filesystem

### 2. **Journal Data Mode** ⚠️ CRITICAL  
- **Monolithic**: Uses `tune2fs -o journal_data` for enhanced data integrity
- **Modular**: Missing this configuration
- **Impact**: Reduced protection against data loss during power failures

### 3. **System Optimizations**
- **Missing**: `vm.swappiness=10` (reduced swapping)
- **Missing**: Faster systemd timeouts (10s vs default 90s)
- **Impact**: Slower boot times, less optimal for embedded use

## Features Already Present

✅ Power button disabled (in `07-base-setup.sh`)  
✅ Network bridge configuration  
✅ NDI service auto-start  
✅ TTY configuration  
✅ Helper scripts (mostly)  
✅ Dual UEFI/BIOS boot support (enhanced in modular)

## Implementation Status

### Fixed in Modular
- Partition labeling (though different approach)
- Boot support for both UEFI and legacy BIOS
- Helper script framework

### Partially Implemented
- Read-only preparation exists but is commented out
- Some helper scripts defined but missing ro/rw utilities

### Not Implemented
- Journal data mode
- System optimizations
- Complete power-failure resistance

## Recommendations

1. **Immediate Fix**: Add the `14-power-resistance.sh` module to restore critical features
2. **Update Version**: Bump to v1.3.1 after fixes
3. **Testing Required**: Verify power-failure resistance after implementation
4. **Documentation**: Update build documentation to reflect these safety features

## Risk Assessment

**Current Risk Level**: HIGH
- Without read-only root and journal data mode, the system is vulnerable to filesystem corruption during power failures
- This defeats the purpose of an embedded/appliance system

**After Fixes**: LOW
- System will match the robustness of the original monolithic version
- Suitable for production embedded use

## Files to Modify

1. `/scripts/build-ndi-usb-modular.sh` - Add new module source
2. `/scripts/build-modules/00-variables.sh` - Update version
3. `/scripts/build-modules/11-filesystem.sh` - Fix UUID handling
4. Add `/scripts/build-modules/14-power-resistance.sh` - New module

## Verification Steps

After applying fixes:
```bash
# Check filesystem mount status
mount | grep " / "  # Should show 'ro'

# Check journal mode
tune2fs -l /dev/sdb3 | grep "Journal mode"  # Should show 'data'

# Test helper commands
ndi-bridge-rw  # Should remount read-write
ndi-bridge-ro  # Should remount read-only
ndi-bridge-info  # Should show "Root: read-only (protected)"
```