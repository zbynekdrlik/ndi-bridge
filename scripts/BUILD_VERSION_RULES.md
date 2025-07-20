# Build Script Version Management Rules

## Version Format
Build script version follows semantic versioning: `MAJOR.MINOR.PATCH`

## Version Update Rules

### When to Update Version
The build script version MUST be updated whenever ANY change is made to `build-ndi-usb-linux-final.sh`:

1. **MAJOR version** - Increment when making incompatible changes:
   - Changing partition scheme
   - Switching base OS version (e.g., Ubuntu 22.04 to 24.04)
   - Major architectural changes

2. **MINOR version** - Increment when adding functionality:
   - Adding new tools or packages
   - Adding new configuration features
   - Adding new helper scripts
   - Improving existing features

3. **PATCH version** - Increment for bug fixes:
   - Fixing installation issues
   - Correcting configuration errors
   - Fixing typos or minor issues

### How to Update Version

When making changes to `build-ndi-usb-linux-final.sh`:

1. Update the version in the script header:
   ```bash
   # Build Script Version: X.Y.Z
   # Last Updated: YYYY-MM-DD
   ```

2. Update the version in the TTY2 menu display (around line 432):
   ```bash
   echo "  Build Script: X.Y.Z"
   ```

3. Update the version saved to the build info file (around line 285):
   ```bash
   echo "X.Y.Z" > /etc/ndi-bridge/build-script-version
   ```

4. Add a comment in the commit message mentioning the version bump:
   ```
   feat: Add network monitoring tools (bump build script to 1.1.0)
   ```

### Version History Tracking
Keep track of version changes in commit messages. Each version change should clearly describe what was modified.

### Checking Version on Running System
Users can check the build script version on a running system:
- Via SSH: `ndi-bridge-info`
- On console TTY2: Shows in the system information section
- File location: `/etc/ndi-bridge/build-script-version`

## Current Versions

- **NDI-Bridge Binary**: 2.1.4 (latest change: version bump only)
- **Build Script**: 1.0.0 (initial versioned release)

## NDI-Bridge Version History

Recent version changes:
- **2.1.4**: Version bump only (no functional changes from 2.1.3)
- **2.1.3**: Added detailed frame timing diagnostics
- **2.1.2**: Pure busy-wait implementation for stable 60fps
- **2.1.1**: FPS fix for non-blocking poll
- **2.1.0**: Extreme low latency with busy-wait and CPU affinity