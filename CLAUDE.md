# CLAUDE.md - NDI Bridge Development Guide

## CRITICAL: Modular Architecture Rules

**NEVER CREATE INLINE SCRIPTS OR FILES IN BUILD MODULES!**
- **Scripts**: ALL must be in `scripts/helper-scripts/` as separate files
- **Service Files**: Should be in dedicated directory structure (not inline)
- **Config Files**: Should be in appropriate directories as separate files
- Build modules (00-15) should ONLY copy/install, NEVER generate content inline
- Module 12 (`12-helper-scripts.sh`) handles ALL script installation
- This prevents files being overwritten by later modules
- Violating this causes deployment of old/wrong versions

**Why this matters:**
- Module execution order means later modules overwrite earlier ones
- Inline generation makes code unmaintainable and hard to debug
- Prevents proper version control of individual components
- Creates massive, unreadable build modules (some had 700+ lines!)
- This has caused repeated deployment failures with wrong versions

**Current Technical Debt (TO BE FIXED):**
- 15 systemd service files still created inline across 7 modules
- These should be extracted to proper directory structure
- Build modules should use `cp` instead of `cat > ... << EOF`

## Git Workflow Rules

**ALWAYS CREATE PR EARLY:**
1. After creating a feature branch, immediately push and create a PR
2. This enables frequent reviews and feedback during development
3. Use draft PRs for work in progress: `gh pr create --draft`
4. Push commits regularly to keep PR updated

## CRITICAL: USB Image Build Rules

**ALWAYS DO:**
1. Run from repository ROOT: `cd /mnt/c/Users/newlevel/Documents/GitHub/ndi-bridge`
2. Increment version: Edit `scripts/build-modules/00-variables.sh` → `BUILD_SCRIPT_VERSION`
3. Run build: `sudo ./build-image-for-rufus.sh` (auto-redirects to log)
4. Monitor logs: `tail -f build-logs/image-build-*.log`

**NEVER DO:**
- Run build from `build/` directory (causes "file not found" errors)
- Forget to increment version (can't identify deployed devices)

**Build takes 10-15 minutes. Image output: `ndi-bridge.img` (4GB)**

## Quick Commands

### Application Build (AUTO-APPROVED)

**RECOMMENDED: Use the build helper script for foolproof building:**

```bash
# From repository root - handles directory changes automatically
./build.sh                     # Build everything
./build.sh ndi-display         # Build display component only
./build.sh ndi-bridge          # Build capture component only
./build.sh --clean             # Clean and rebuild
./build.sh --help              # Show all options
```

**Manual build (if needed):**
```bash
# CRITICAL: Must be in build/ directory!
cd /mnt/c/Users/newlevel/Documents/GitHub/ndi-bridge/build
make ndi-display -j$(nproc)    # Display component
make ndi-bridge -j$(nproc)     # Capture component
make -j$(nproc)                # Everything
```

**Common build errors:**
- `"No rule to make target"` → Wrong directory! Use `./build.sh` or cd to `build/`
- `"Command not found: cmake"` → Run: `sudo apt install cmake build-essential`
- `"Cannot find NDI"` → Run: `./setup-build-environment.sh` from repo root

**Build Output**: `build/bin/` (e.g., `build/bin/ndi-display`)

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

## NDI Display System (v1.6.8+)

### Display Output Architecture

The NDI display system uses DRM/KMS (Direct Rendering Manager/Kernel Mode Setting) exclusively:

**Hardware-Accelerated DRM/KMS** (Optimized for Intel N100)
   - Uses GPU hardware planes for scaling when available
   - Zero-copy scaling from Full HD NDI streams to 4K displays
   - Supports Intel UHD Graphics (24 EU) hardware acceleration
   - Automatic aspect ratio preservation with letterboxing
   - Double buffering with page flipping for smooth playback
   - Falls back to software scaling within DRM if hardware planes unavailable
   - CPU-based bilinear scaling when needed

### Scaling and Resolution Support

The display system automatically handles resolution mismatches:
- **Full HD NDI → 4K Display**: Hardware-accelerated upscaling
- **4K NDI → Full HD Display**: Hardware-accelerated downscaling
- **Aspect Ratio Preservation**: Automatic letterboxing/pillarboxing
- **Intel N100 Optimization**: Uses GPU planes for zero-copy scaling

### Key Features
- Single-threaded, low-latency design (matches capture philosophy)
- One binary per stream-display pair for simplicity
- Automatic display detection and EDID parsing
- Real-time status reporting to /var/run/ndi-display/
- Console management with proper TTY allocation

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

## Fast Testing on Running Box (Without USB Reflashing)

For quick iteration during development, you can deploy directly to a running box:

```bash
# Option 1: Deploy specific binaries only (fastest)
sshpass -p newlevel ssh root@10.77.9.143 "systemctl stop ndi-display@1"
sshpass -p newlevel scp build/bin/ndi-display root@10.77.9.143:/opt/ndi-bridge/
sshpass -p newlevel ssh root@10.77.9.143 "systemctl start ndi-display@1"

# Option 2: Use quick-deploy.sh script (if created)
./quick-deploy.sh 10.77.9.143

# Check logs after deployment
sshpass -p newlevel ssh root@10.77.9.143 "journalctl -u ndi-display@1 -n 50"
```

**Note**: The box's SSH may show welcome screen. Add `-o LogLevel=ERROR` to suppress it.
- Use TDD test driven development. Working and full tests sucess are most important part.