# Fixes for Modular Build Script

## Overview
This document describes how to restore the missing power-failure resistance features from the monolithic version to the modular version.

## Changes Required

### 1. Add New Module
Created `14-power-resistance.sh` module that includes:
- Read-only root filesystem configuration
- Power failure resistance (journal data mode)
- System optimization (swappiness, boot timeouts)
- Helper scripts for ro/rw mounting

### 2. Update build-ndi-usb-modular.sh

Add after line 24 (after sourcing module 13):
```bash
source "$SCRIPT_DIR/build-modules/14-power-resistance.sh"
```

Update the `assemble_configuration` function (around line 57) to add:
```bash
    configure_power_resistance
    configure_readonly_root
```

Add after `run_chroot_setup` (around line 119):
```bash
    tune_filesystem
```

### 3. Fix the fstab Issue

The current modular version has a bug in `11-filesystem.sh` where it uses `${USB_DEVICE}3` inside the chroot environment where the variable isn't available.

In `11-filesystem.sh`, line 12 should be changed from:
```bash
UUID=$(blkid -s UUID -o value ${USB_DEVICE}3) / ext4 errors=remount-ro 0 1
```

To use a placeholder that gets replaced later:
```bash
UUID=ROOT_UUID_PLACEHOLDER / ext4 errors=remount-ro 0 1
```

Then in the main script, after mounting but before chroot, add:
```bash
# Get UUIDs and replace in script
ROOT_UUID=$(blkid -s UUID -o value ${USB_DEVICE}3)
EFI_UUID=$(blkid -s UUID -o value ${USB_DEVICE}2)
sed -i "s/ROOT_UUID_PLACEHOLDER/$ROOT_UUID/g" /mnt/usb/tmp/configure-system.sh
sed -i "s/EFI_UUID_PLACEHOLDER/$EFI_UUID/g" /mnt/usb/tmp/configure-system.sh
```

### 4. Missing Script Creation

The `ndi-bridge-show-logs` script is referenced but never created inline. This needs to be added to `10-tty-config.sh` or created as a separate file.

### 5. Version Bump

Update `BUILD_SCRIPT_VERSION` in `00-variables.sh` to `1.3.1` to reflect these fixes.

## Testing

After applying these fixes:
1. The USB should boot with a read-only root filesystem
2. Power failures should not corrupt the filesystem
3. `ndi-bridge-info` should show "Root: read-only (protected)"
4. `ndi-bridge-rw` and `ndi-bridge-ro` commands should work
5. System should boot faster with reduced timeouts

## Benefits

These changes restore:
- Power failure resistance through read-only root and journal data mode
- System optimizations for embedded/appliance use
- Better filesystem integrity protection
- All helper utilities from the monolithic version