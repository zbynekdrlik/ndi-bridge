# CLAUDE.md - Media Bridge Development Guide

## CRITICAL: Dante/Inferno Repository Rule

### ALWAYS USE OFFICIAL GITLAB INFERNO REPOSITORY
**The ONLY authoritative Inferno source is: `https://gitlab.com/lumifaza/inferno`**
- **NEVER use GitHub forks** (teodly or others) for Inferno
- **NEVER reference GitHub as the source** for Inferno
- **GitLab lumifaza is the OFFICIAL active repository** where development happens
- GitHub mirrors are outdated and cause discovery failures
- **NOTE: mrblondin repository mentioned in issue #104 doesn't exist - lumifaza is correct**
- **This mistake has been made multiple times - DO NOT REPEAT IT!**

When working with Dante:
1. Always clone Inferno from: `https://gitlab.com/lumifaza/inferno.git` (NOT GitHub!)
2. For Statime PTPv1 support: Use `https://github.com/teodly/statime.git` branch `inferno-dev`
3. Verify with network-audio-controller: `https://github.com/chris-ritsen/network-audio-controller`

**Repository Verification History:**
- mrblondin/inferno on GitLab: Does NOT exist (403 error)
- lumifaza/inferno on GitLab: EXISTS and is actively maintained
- teodly/inferno on GitHub: Mirror only - DO NOT USE

## CRITICAL: Git and PR Workflow Rules

### NEVER MERGE PRs AUTOMATICALLY
**Claude must NEVER merge pull requests using gh pr merge or any automated method!**
- Pull requests can ONLY be merged by the user through GitHub web interface
- This ensures proper review and approval process
- Claude can create PRs, push commits, but NEVER merge
- If asked to merge, Claude should respond: "Please review and merge PR #XX through GitHub web interface"

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

## Modern Test Suite Architecture (2025)

### Testing Framework: pytest + testinfra
**Industry-standard framework for embedded/hardware testing with SSH-based remote execution**

### Core Testing Principles

#### 1. Atomic Tests - One Test, One Assertion
**CRITICAL: Each test must validate exactly ONE thing**
```python
# BAD: Multiple assertions in one test
def test_capture():
    assert device_exists()
    assert service_active()
    assert fps == 30
    
# GOOD: Atomic tests
def test_capture_device_exists():
    """Test that /dev/video0 exists."""
    assert host.file("/dev/video0").exists

def test_capture_service_active():
    """Test that ndi-capture service is running."""
    assert host.service("ndi-capture").is_running

def test_capture_fps_stable():
    """Test that capture maintains 30fps."""
    metrics = host.file("/var/run/media-bridge/fps").content_string
    assert float(metrics) >= 29.0
```

#### 2. AAA Pattern (Arrange-Act-Assert)
**Every test follows this structure:**
```python
def test_stabilization_duration():
    # Arrange: Set up test conditions
    host.run("systemctl restart ndi-capture")
    
    # Act: Perform the action
    time.sleep(30)
    
    # Assert: Verify the outcome
    state = host.file("/var/run/media-bridge/capture_state").content_string
    assert state == "RUNNING"
```

#### 3. Test Organization by Category
```
tests/
├── unit/                    # Pure logic tests (no device needed)
├── component/               # Single component atomic tests (checking existence/state)
│   ├── capture/            # Atomic capture tests
│   │   ├── test_device_detection.py    # Device exists, permissions
│   │   ├── test_service_status.py      # Service running/enabled
│   │   └── test_fps_monitoring.py      # Metrics files exist
│   ├── display/            # Atomic display tests
│   │   ├── test_display_capability.py  # DRM devices, binaries exist
│   │   └── test_ndi_display_service.py # Service template valid
│   ├── audio/              # Atomic audio tests
│   ├── network/            # Atomic network tests
│   └── [component]/        # Each component gets atomic tests
├── integration/            # Multi-component interaction & functional tests
│   ├── test_capture_to_ndi.py         # Capture + NDI interaction
│   └── test_display_functional.py     # FUNCTIONAL: Actually plays streams
├── system/                 # End-to-end system tests
├── performance/            # Benchmarks and metrics
└── fixtures/               # Shared test utilities
```

**Expected Results on Clean Media Bridge**:
- ~140 tests should pass
- Some skips are normal (optional features like intercom)
- Zero failures on properly configured device

#### Quick Test Commands Reference

```bash
# Just test if device is working (critical tests only, fast)
pytest -m critical --host DEVICE_IP --ssh-key ~/.ssh/ndi_test_key -q

# Full validation before deployment (all tests, detailed)
pytest tests/ --host DEVICE_IP --ssh-key ~/.ssh/ndi_test_key -v

# Debug specific component issues
pytest tests/component/capture/ --host DEVICE_IP --ssh-key ~/.ssh/ndi_test_key -vv

# Generate HTML report
pytest tests/ --host DEVICE_IP --ssh-key ~/.ssh/ndi_test_key --html=report.html
```

### Writing New Tests

#### 1. Create Atomic Test File
```python
# tests/component/capture/test_new_feature.py
import pytest

def test_specific_behavior(host):
    """Test one specific behavior."""
    # One test, one assertion
    result = host.run("command")
    assert result.succeeded
```

#### 2. Use Fixtures for Common Operations
```python
@pytest.fixture
def restart_service(host):
    """Fixture to restart a service."""
    def _restart(service_name):
        host.run(f"systemctl restart {service_name}")
        time.sleep(2)
    return _restart

def test_service_recovery(host, restart_service):
    restart_service("ndi-capture")
    assert host.service("ndi-capture").is_running
```

#### 3. Parallel Test Execution
Tests are designed to run in parallel by default:
- Each test is independent (no shared state)
- Fixtures handle setup/teardown
- Use `pytest-xdist` for auto-parallelization

### Migration from Bash Tests

**Current State**: 83 tests in 11 bash files (violates atomic principle)
**Target State**: Each test as separate Python function

**Migration Process**:
1. Identify logical test units in bash scripts
2. Create atomic pytest function for each
3. Place in appropriate category directory
4. Use testinfra for SSH operations

**Atomic Test Example**:
```python
# Each test validates exactly one thing
def test_capture_device_present(host):
    assert host.file("/dev/video0").exists

def test_capture_service_enabled(host):
    assert host.service("ndi-capture").is_enabled

def test_capture_fps_nominal(host):
    fps = float(host.file("/var/run/media-bridge/fps").content_string)
    assert 29.0 <= fps <= 31.0
```

### CI/CD Integration

```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
      - run: pip install -r tests/requirements.txt
      - run: pytest --host ${{ secrets.TEST_DEVICE_IP }}
```

### Best Practices

1. **Test Independence**: Each test must be runnable in isolation
2. **Fast Feedback**: Component tests <1s, integration <5s
3. **Clear Naming**: `test_<component>_<behavior>_<expected_result>`
4. **No Test Interdependencies**: Tests never depend on execution order
5. **Use Markers**: Tag tests appropriately for selective execution
6. **Fixture Reuse**: Common operations in fixtures, not duplicated
7. **Descriptive Docstrings**: Each test has clear documentation

### Known Issues That Took 10+ Builds to Find:
- Menu `read` commands need `< /dev/tty` when called from other scripts
- Services must be enabled AND started
- kbd package required for chvt but was missing
- Stream names must match exactly (e.g., "MEDIA-BRIDGE (USB Capture)")

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

## Known Issues & Solutions

| Issue | Solution |
|-------|----------|
| Build fails instantly | Wrong directory - must run from repo root |
| Can't find build logs | Check `build-logs/` subdirectory |
| mDNS fails in WSL | Use IP address or test from Windows |
| --version hangs | Fixed in main.cpp - exits before init |
| Scripts not updating | Removed inline scripts from 10-tty-config.sh |
| Chrome shows no audio devices | Reboot device, select USB device in Chrome |
| Audio device locked after testing | Stale PipeWire modules can lock devices - reboot clears state |

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

## Testing with pytest

The project uses **pytest + testinfra** for atomic testing (one test = one assertion).

### Running Tests
```bash
# Configure test IP (persistent across sessions)
nano tests/test_config.yaml  # Set: host: 10.77.9.188

# Run all tests
python3 -m pytest tests/ --host 10.77.9.188 --ssh-key ~/.ssh/ndi_test_key -q --tb=no

# Run specific component tests
python3 -m pytest tests/component/core/ --host 10.77.9.188 --ssh-key ~/.ssh/ndi_test_key -q
python3 -m pytest tests/component/capture/ --host 10.77.9.188 --ssh-key ~/.ssh/ndi_test_key -q

# Use helper scripts
./tests/run_all_tests.sh        # Runs all test categories
./tests/test-device.sh           # Auto-handles SSH key changes for reflashed devices
```

### Test Configuration Priority
1. Command line: `--host 10.77.9.188`
2. Config file: `tests/test_config.yaml`
3. Environment: `export NDI_TEST_HOST=10.77.9.188`
4. Default: `10.77.9.143`

### Test Categories and Markers
```bash
# Run by category
pytest -m critical       # Must-pass tests only
pytest -m capture       # Video capture tests
pytest -m network       # Network functionality
pytest -m "not slow"    # Skip slow tests (>5s)
```

### SSH Key Handling for Reflashed Devices
When testing multiple devices on same IP, add to `~/.ssh/config`:
```bash
Host 10.77.9.*
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```
Or use `./tests/test-device.sh` which handles this automatically.