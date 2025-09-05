# CLAUDE.md - Media Bridge Development Guide

## CRITICAL: Git and PR Workflow Rules

### NEVER MERGE PRs AUTOMATICALLY
**Claude must NEVER merge pull requests using gh pr merge or any automated method!**
- Pull requests can ONLY be merged by the user through GitHub web interface
- This ensures proper review and approval process
- Claude can create PRs, push commits, but NEVER merge
- If asked to merge, Claude should respond: "Please review and merge PR #XX through GitHub web interface"

## CRITICAL: Documentation Management Rules

### Documentation Structure (STRICTLY ENFORCED)
**Root directory may ONLY contain:**
- `README.md` - Project overview and quick start
- `CLAUDE.md` - This development guide

**ALL other documentation MUST be in `docs/` folder:**
- Technical documentation → `docs/`
- Architecture documents → `docs/`
- Build/test/contribution guides → `docs/`
- Any new .md files → `docs/`

### Documentation Rules
1. **NEVER create .md files in root directory** (except README.md and CLAUDE.md)
2. **NEVER duplicate information** - single source of truth only
3. **ALWAYS update existing docs** instead of creating new ones
4. **ALWAYS link to docs/** from README.md when referencing detailed information
5. **Architecture documents are MANDATORY** - must be updated with ANY architectural changes

### PipeWire Specific Rule
**When modifying ANY PipeWire functionality:**
- Update `docs/PIPEWIRE.md` IMMEDIATELY
- This is the ONLY authoritative source for PipeWire architecture
- No PipeWire information should exist elsewhere

### Documentation Workflow
```bash
# Wrong: Creating documentation in root
touch NEW_FEATURE.md  # ❌ NEVER DO THIS

# Correct: Documentation goes in docs/
touch docs/NEW_FEATURE.md  # ✓ Always use docs/ folder

# Better: Update existing relevant doc
edit docs/EXISTING_CATEGORY.md  # ✓ Prefer updating existing docs
```

## NAMING CONVENTIONS

### Project Name: Media Bridge
The project has been renamed from "NDI Bridge" to "Media Bridge" to better reflect its multi-purpose media handling capabilities.

### File Naming Guidelines
- **Helper Scripts**: Use `media-bridge-*` prefix (e.g., `media-bridge-info`, `media-bridge-logs`)
- **Application Binaries**: Keep descriptive names (`ndi-capture`, `ndi-display`) - these describe what they do, not the project name
- **Service Files**: Use `media-bridge-*` prefix for project services
- **Configuration Paths**: Use `/etc/media-bridge/`, `/var/run/media-bridge/`, etc.
- **C++ Namespace**: Keep as `ndi_bridge` (internal code structure, not user-facing)

### Why This Naming Strategy
- Helper scripts are project utilities → use project name (`media-bridge-*`)
- Application binaries describe their function → `ndi-capture` captures to NDI, `ndi-display` displays from NDI
- This creates clear distinction between project utilities and functional applications

## WEB INTERFACE ARCHITECTURE (2025 Standard)

### Technology Stack
**Backend**: FastAPI (Python)
**Frontend**: Vue 3 (Options API) + Vuetify 3
**Real-time**: WebSockets for live updates
**Deployment**: No build step - Vue from CDN

### Why This Stack
1. **AI Coding Consistency**: Enforced structure prevents context loss
2. **Mobile-First**: Vuetify provides Material Design components
3. **No Build Complexity**: Deploy by copying files
4. **Real-time Updates**: Native WebSocket support
5. **Shell Integration**: Python subprocess for existing scripts

### Project Structure (MUST FOLLOW)
```
web/
├── backend/
│   ├── main.py                  # FastAPI app entry
│   ├── api/
│   │   ├── __init__.py
│   │   └── [feature].py         # Feature-specific endpoints
│   ├── services/
│   │   ├── __init__.py
│   │   ├── shell_executor.py    # Shell command wrapper
│   │   └── state_manager.py     # State management
│   └── models/
│       ├── __init__.py
│       └── schemas.py           # Pydantic models
├── frontend/
│   ├── index.html               # Vue app entry
│   ├── js/
│   │   ├── app.js               # Main Vue app
│   │   ├── components/          # Vue components
│   │   └── services/            # API/WebSocket clients
│   └── css/
│       └── overrides.css        # Minimal custom styles
└── requirements.txt             # FastAPI, uvicorn only
```

### Component Pattern (MUST USE)
```javascript
// Every Vue component MUST follow this structure
export default {
    name: 'ComponentName',
    template: `...`,  // Vuetify components only
    data() {
        return {
            // All reactive data here
        }
    },
    mounted() {
        // WebSocket connections here
    },
    methods: {
        // All methods here
    },
    computed: {
        // Computed properties here
    }
}
```

### API Pattern (MUST USE)
```python
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/api/module")

class RequestModel(BaseModel):
    """Always use Pydantic models"""
    field: type

@router.post("/endpoint")
async def endpoint_name(request: RequestModel):
    """Always async, always typed"""
    # Shell execution
    result = await execute_command("script", ["args"])
    # WebSocket broadcast
    await broadcast_state({"key": "value"})
    return {"status": "success"}
```

### State Management Rules
1. **ALL state lives in backend** (FastAPI)
2. **Frontend is display-only** (Vue reflects backend state)
3. **Updates via WebSocket** (No polling)
4. **Configuration persistence** must be explicit user action

### Mobile-First Design Rules
1. **Use Vuetify components exclusively** - No custom UI elements
2. **Touch targets minimum 48x48px** - Material Design spec
3. **Bottom navigation on mobile** - Thumb-friendly
4. **Responsive breakpoints**: xs (mobile), sm (tablet), md+ (desktop)
5. **Test on actual mobile devices** - Not just browser resize

## CRITICAL: Debugging & Testing Requirements

**NEVER assume a fix works without testing on actual hardware!**

### Common Mistakes to Avoid:
1. **Testing on box but not fixing in repository** - Always update code after confirming fix
2. **Assuming services work without checking `systemctl is-enabled`** - Many issues from disabled services
3. **Not testing menu systems interactively** - Read commands fail in non-interactive contexts
4. **Making complex menus that can't be tested** - Keep it simple and testable
5. **Not verifying after reboot** - Always test persistence

### Proper Debugging Workflow:
1. Test on actual deployed box (not just build)
2. Make ONE atomic change at a time
3. Test → Reboot → Test again
4. If works: Document exact fix
5. Apply fix to repository IMMEDIATELY
6. Never leave fixes only on test box

### Testing Success Criteria:
**ONLY 100% test success can be considered "working"!**
- If ANY test component fails, the feature is NOT working
- Do NOT claim success when critical components fail
- USB Audio detection failure = Intercom NOT working
- Partial success = Complete failure
- All tests must pass before declaring feature operational

## Testing

**SINGLE SOURCE OF TRUTH: See [docs/TESTING.md](docs/TESTING.md)**

### Quick Commands for Claude (AI Assistant)

**When user says "run tests" or "run all tests", ALWAYS use test-device.sh:**

```bash
cd /home/newlevel/devel/ndi-bridge

# Run ALL 433 tests (complete suite)
./tests/test-device.sh 10.77.8.124

# Run specific test category  
./tests/test-device.sh 10.77.8.124 tests/component/audio/

# Run critical tests only
./tests/test-device.sh 10.77.8.124 -m critical

# Quick SSH verification
./tests/test-device.sh 10.77.8.124 --collect-only
```

**CRITICAL RULES:**
- **NEVER run pytest directly** - always use `test-device.sh`
- **IP address is REQUIRED** as first parameter
- **test-device.sh handles ALL SSH setup** automatically
- **Complete documentation** at [docs/TESTING.md](docs/TESTING.md)

### Test Suite Overview
- **433 total tests** across comprehensive suite
- **~400+ should pass** on healthy Media Bridge device  
- **Hardware dependencies** cause expected skips
- **Complete validation** takes 5-10 minutes

## CRITICAL: Modular Architecture Rules

**NEVER CREATE INLINE SCRIPTS OR FILES IN BUILD MODULES!**
- **Scripts**: ALL must be in `scripts/helper-scripts/` as separate files
- **Service Files**: Should be in dedicated directory structure (not inline)
- **Config Files**: Should be in appropriate directories as separate files
- Build modules (00-15) should ONLY copy/install, NEVER generate content inline
- Module 12 (`12-helper-scripts.sh`) handles ALL script installation
- This prevents files being overwritten by later modules
- Violating this causes deployment of old/wrong versions

**FEATURE IMPLEMENTATION RULES:**
- **Every feature must be installed during image build** - NO post-install scripts
- **All dependencies installed in build modules** - Users should never run install scripts  
- **Services enabled by default** if they're core features (like intercom)
- **Consistent approach** - All features follow same pattern (not different for each)
- **Modular files** - Split features across multiple small files, not one big file
- **No conditional installation** - Everything needed is in the image

**Why this matters:**
- Module execution order means later modules overwrite earlier ones
- Inline generation makes code unmaintainable and hard to debug
- Prevents proper version control of individual components
- Creates massive, unreadable build modules (some had 700+ lines!)
- This has caused repeated deployment failures with wrong versions
- Inconsistent approaches confuse users and break expectations

**Current Technical Debt (TO BE FIXED):**
- 15 systemd service files still created inline across 7 modules
- These should be extracted to proper directory structure
- Build modules should use `cp` instead of `cat > ... << EOF`

## TODO Tracking with GitHub Issues

**ALWAYS use GitHub Issues for TODO tracking, not TODO.md files:**
- Create issues with `gh issue create`
- List issues with `gh issue list`
- View specific issue with `gh issue view <number>`
- Close completed issues with `gh issue close <number>`

**Why GitHub Issues instead of TODO.md:**
- No merge conflicts between branches
- Single source of truth across all branches
- Better collaboration and tracking
- Can link issues to PRs
- Works perfectly with multi-branch workflow

**Example workflow:**
```bash
# Create a new task
gh issue create --title "Fix blinking dashboard" --body "Details..." --label "bug"

# List all open issues
gh issue list

# Start working on issue #25
gh issue view 25
git checkout -b fix-issue-25

# After completing, reference in commit
git commit -m "Fix blinking dashboard issue

Fixes #25"
```

## Git Workflow Rules

**ALWAYS CREATE PR EARLY:**
1. After creating a feature branch, immediately push and create a PR
2. This enables frequent reviews and feedback during development
3. Use draft PRs for work in progress: `gh pr create --draft`
4. Push commits regularly to keep PR updated

## CRITICAL: USB Image Build Rules

**ALWAYS DO:**
1. Run from repository ROOT: `cd /mnt/c/Users/newlevel/Documents/GitHub/media-bridge`
2. Increment version: Edit `scripts/build-modules/00-variables.sh` → `BUILD_SCRIPT_VERSION`
3. Run build: `sudo ./build-image-for-rufus.sh > build.log 2>&1 &` (MUST redirect ALL output to prevent Claude crashes)
4. Monitor logs: `tail -f build.log` or check build-logs directory

**NEVER DO:**
- Run build from `build/` directory (causes "file not found" errors)
- Forget to increment version (can't identify deployed devices)

**Build takes 10-15 minutes. Image output: `media-bridge.img` (8GB)**

## Clean Repository Build Process

**Building USB Image from Freshly Cloned Repository:**

1. **Clone and enter repository:**
```bash
git clone https://github.com/yourusername/media-bridge.git
cd media-bridge
```

2. **Setup build environment (installs dependencies and NDI SDK):**
```bash
./setup-build-environment.sh
```
This will:
- Install all build dependencies (cmake, libv4l-dev, etc.)
- Download and install NDI SDK v6 to project directory
- Verify the installation

3. **Build application binaries:**
```bash
./build.sh
```
This creates ndi-capture and ndi-display binaries in `build/bin/`

4. **Increment version number:**
```bash
# Edit scripts/build-modules/00-variables.sh
# Change BUILD_SCRIPT_VERSION (e.g., "1.9.5" → "1.9.6")
```

5. **Build USB image:**
```bash
sudo ./build-image-for-rufus.sh > build.log 2>&1 &
tail -f build.log  # Monitor progress
```
Build takes 10-15 minutes. Output: `media-bridge.img` (8GB)

**Common Issues & Solutions:**
- `losetup package not found` → Fixed: use util-linux package instead
- `NDI SDK directory not found` → Fixed: installer extracts to current dir, not home
- `libndi.so.6.2.0 not found` → Fixed: NDI SDK v6 has libndi.so.6.2.1

## Quick Commands

### Application Build (AUTO-APPROVED)

**RECOMMENDED: Use the build helper script for foolproof building:**

```bash
# From repository root - handles directory changes automatically
./build.sh                     # Build everything
./build.sh ndi-display         # Build display component only
./build.sh ndi-capture         # Build capture component only
./build.sh --clean             # Clean and rebuild
./build.sh --help              # Show all options
```

**Manual build (if needed):**
```bash
# CRITICAL: Must be in build/ directory!
cd /mnt/c/Users/newlevel/Documents/GitHub/media-bridge/build
make ndi-display -j$(nproc)    # Display component
make ndi-capture -j$(nproc)    # Capture component
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
./ndi-capture --version  # Should return version immediately
```

### USB Appliance Commands
```bash
media-bridge-info         # System status
media-bridge-logs         # View logs
media-bridge-set-name     # Change NDI name
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
- Config: `/etc/nginx/sites-available/media-bridge`

## Unified PipeWire Audio Architecture

**CRITICAL: All PipeWire-related work MUST reference and update docs/PIPEWIRE.md**

### Core Architecture (v2.2+)
Media Bridge uses a **unified system-wide PipeWire instance** for all audio management:
- Single PipeWire process running as root (no user sessions)
- WirePlumber for session/policy management
- PulseAudio compatibility via pipewire-pulse
- Virtual devices isolate Chrome from hardware

### Key Components
1. **System Services**: pipewire-system, pipewire-pulse-system, wireplumber-system
2. **Virtual Devices**: intercom-speaker, intercom-microphone (prevents device locking)
3. **Configuration**: `/etc/pipewire/`, `/etc/wireplumber/`
4. **Runtime**: `/var/run/pipewire/`

### Documentation Requirements
**MANDATORY: When modifying ANY PipeWire-related functionality:**
1. First read `docs/PIPEWIRE.md` for current architecture
2. Make changes following documented patterns
3. Update `docs/PIPEWIRE.md` with ALL changes:
   - Service modifications
   - Configuration changes
   - New audio routing
   - Test additions
4. Ensure consistency across all files

### Quick Reference
- **Check audio**: `pactl list sinks` (uses system PipeWire)
- **Virtual devices**: Created by media-bridge-audio-manager
- **Low latency**: 256 samples @ 48kHz (5.33ms)
- **Testing**: See `tests/component/audio/test_unified_pipewire.py`

For complete details, see **docs/PIPEWIRE.md** - the authoritative source for PipeWire architecture.

## Known Issues & Solutions

| Issue | Solution |
|-------|----------|
| Build fails instantly | Wrong directory - must run from repo root |
| Can't find build logs | Check `build-logs/` subdirectory |
| mDNS fails in WSL | Use IP address or test from Windows |
| --version hangs | Fixed in main.cpp - exits before init |
| Scripts not updating | Removed inline scripts from 10-tty-config.sh |
| Chrome shows no audio devices | Check virtual devices: `pactl list sources` |
| Audio device locked | Virtual devices prevent locking - check wireplumber logs |
| PipeWire not starting | Check service deps: `systemctl status pipewire-system wireplumber-system` |

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
2. `media-bridge-collector` service parses journalctl
3. Writes to `/var/run/media-bridge/` tmpfs files
4. `media-bridge-welcome` reads and displays on TTY2

### Btrfs Filesystem
- Root filesystem uses Btrfs for power failure resistance
- Copy-on-Write (CoW) for data integrity
- Optimized for flash media with SSD mode
- Fast boot with space_cache=v2 and no compression

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
sshpass -p newlevel scp build/bin/ndi-display root@10.77.9.143:/opt/media-bridge/
sshpass -p newlevel ssh root@10.77.9.143 "systemctl start ndi-display@1"

# Option 2: Use quick-deploy.sh script (if created)
./quick-deploy.sh 10.77.9.143

# Check logs after deployment
sshpass -p newlevel ssh root@10.77.9.143 "journalctl -u ndi-display@1 -n 50"
```

**Note**: The box's SSH may show welcome screen. Add `-o LogLevel=ERROR` to suppress it.
- Use TDD test driven development. Working and full tests sucess are most important part.

# important-instruction-reminders

**TDD Philosophy**: Use test-driven development. Working tests and full test success are the most important part.

**Repository Integration Rule**: Always when anything is fixed on testing device, fix has to be incorporated to repository. It is forbidden to start services on testing box without verifying and fixing in repository - this is why they weren't started in the first place!

**PipeWire Expertise**: You are a PipeWire implementation expert, always use original web documentation to support your knowledge of using PipeWire.