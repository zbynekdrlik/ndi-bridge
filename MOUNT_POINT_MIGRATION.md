# Mount Point Migration Plan

## Problem
- Currently hardcoded to `/mnt/usb` in 17 files
- Prevents concurrent builds in different folders
- System-wide mount conflicts between builds

## Solution
Use repository-local mount point: `./build-mount/`

## Benefits
1. **Isolation**: Each repository has its own mount space
2. **Concurrent builds**: Multiple builds can run simultaneously
3. **No conflicts**: Different branches won't interfere
4. **Easy cleanup**: Just delete local folder

## Implementation Status
✅ Added `MOUNT_POINT` variable in `00-variables.sh`
⏳ Need to update 17 files to use `$MOUNT_POINT`

## Files to Update
- scripts/build-ndi-usb-modular.sh
- scripts/build-modules/04-mount.sh
- scripts/build-modules/05-debootstrap.sh
- scripts/build-modules/06-system-config.sh
- scripts/build-modules/07-base-setup.sh
- scripts/build-modules/08-network.sh
- scripts/build-modules/09-ndi-capture-service.sh
- scripts/build-modules/10-ndi-display-service.sh
- scripts/build-modules/11-intercom-chrome.sh
- scripts/build-modules/12-tty-config.sh
- scripts/build-modules/13-filesystem.sh
- scripts/build-modules/14-helper-scripts.sh
- scripts/build-modules/15-time-sync.sh
- scripts/build-modules/16-power-resistance.sh
- scripts/build-modules/17-web-interface.sh
- scripts/build-modules/01a-cleanup.sh

## Update Rules
1. Direct shell commands: `/mnt/usb` → `$MOUNT_POINT`
2. Heredoc file paths: `/mnt/usb/tmp/file` → `$MOUNT_POINT/tmp/file`
3. Inside chroot/heredocs: Leave as-is (no mount point needed)

## Example Changes

### Before:
```bash
mkdir -p /mnt/usb
mount $PART2 /mnt/usb
```

### After:
```bash
mkdir -p $MOUNT_POINT
mount $PART2 $MOUNT_POINT
```

## Testing Required
- [ ] Single build works
- [ ] Concurrent builds in different folders work
- [ ] Cleanup properly removes local mount directory
- [ ] No permission issues with local mount