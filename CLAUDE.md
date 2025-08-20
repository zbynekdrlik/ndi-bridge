# CLAUDE.md - NDI Bridge Development Guide

## CRITICAL: USB Image Build Rules

**ALWAYS DO:**
1. Run from repository ROOT: `cd /mnt/c/Users/newlevel/Documents/GitHub/ndi-bridge`
2. Increment version: Edit `scripts/build-modules/00-variables.sh` → `BUILD_SCRIPT_VERSION`
3. Redirect output: `sudo ./build-image-for-rufus.sh > build.log 2>&1 &`
4. Monitor logs: `tail -f build-logs/image-build-*.log`

**NEVER DO:**
- Run build from `build/` directory (causes "file not found" errors)
- Run build without output redirection (crashes terminal)
- Forget to increment version (can't identify deployed devices)

**Build takes 10-15 minutes. Image output: `ndi-bridge.img` (4GB)**

## Quick Commands

### Application Build
```bash
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
```

### Testing
```bash
# After changes, ALWAYS run:
npm run lint       # If exists
npm run typecheck  # If exists
./ndi-bridge --version  # Should return version immediately
```

### USB Appliance Commands
```bash
ndi-bridge-info         # System status
ndi-bridge-logs         # View logs
ndi-bridge-set-name     # Change NDI name
ndi-bridge-rw           # Mount filesystem read-write
ndi-bridge-ro           # Return to read-only
```

## Project Structure

### Core Application (`src/`)
- `main.cpp` - Entry point, handles --version
- `common/app_controller.h` - Main coordinator
- `common/logger.h` - Logging with metrics() for structured data
- `linux/v4l2/v4l2_capture.cpp` - Linux capture (emits metrics)
- `common/ndi_sender.h` - NDI transmission

### USB Build System (`scripts/`)
- `build-modules/00-variables.sh` - **VERSION HERE!**
- `build-modules/` - Numbered build steps (00-14)
- `helper-scripts/` - All runtime scripts (single source of truth)
- **NO inline scripts in build modules!**

### Web Interface
- URL: `http://device.local/` (admin/newlevel)
- Terminal: Persistent tmux session via wetty
- Config: `/etc/nginx/sites-available/ndi-bridge`

## Known Issues & Solutions

| Issue | Solution |
|-------|----------|
| Build fails instantly | Wrong directory - must run from repo root |
| Can't find build logs | Check `build-logs/` subdirectory |
| mDNS fails in WSL | Use IP address or test from Windows |
| --version hangs | Fixed in main.cpp - exits before init |
| Scripts not updating | Removed inline scripts from 10-tty-config.sh |

## Architecture Notes

### Metrics Collection Pipeline
1. `v4l2_capture.cpp` emits: `METRICS|FPS:30|FRAMES:1234|DROPPED:0`
2. `ndi-bridge-collector` service parses journalctl
3. Writes to `/var/run/ndi-bridge/` tmpfs files
4. `ndi-bridge-welcome` reads and displays on TTY2

### Read-Only Filesystem
- Root filesystem is read-only for power failure protection
- `/tmp`, `/var/log`, `/run` are tmpfs (RAM)
- Use `ndi-bridge-rw` to make changes
- Always return to read-only with `ndi-bridge-ro`

### Time Sync (Critical for Quality)
- PTP primary (microsecond precision)
- NTP fallback (millisecond precision)
- Coordinator service manages failover
- Status shown on TTY2 welcome screen

## Development Workflow

1. **Before changes**: Check existing patterns in codebase
2. **Make changes**: Follow existing code style (no comments unless asked)
3. **Test locally**: Run lint/typecheck if available
4. **Build image**: Increment version, build from root, monitor logs
5. **Deploy**: Flash with Rufus, test on device
6. **Verify**: Check TTY2 for version, SSH for detailed testing