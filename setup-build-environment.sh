#!/bin/bash
# Media Bridge Build Environment Setup Script
# Automatically installs all dependencies needed to compile Media Bridge and create USB appliances
# Works on Ubuntu/Debian (including WSL) and can be extended for other distros

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Configuration
NDI_SDK_VERSION="6.2.1"
NDI_SDK_URL="https://downloads.ndi.tv/SDK/NDI_SDK_Linux/Install_NDI_SDK_v6_Linux.tar.gz"
NDI_SDK_DIR="NDI SDK for Linux"

# Check for dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" || "$1" == "-n" ]]; then
    DRY_RUN=true
    log_warn "DRY-RUN MODE: No system changes will be made"
    SUDO="echo [DRY-RUN] sudo"
fi

# Show help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Media Bridge Build Environment Setup"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run, -n    Show what would be done without making changes"
    echo "  --help, -h       Show this help message"
    echo ""
    echo "This script will:"
    echo "  - Detect system type (Linux/WSL)"
    echo "  - Install build dependencies via apt"
    echo "  - Download and install NDI SDK v$NDI_SDK_VERSION"
    echo "  - Install USB creation tools (parted, debootstrap, etc.)"
    echo "  - Verify complete build environment"
    echo "  - Test Media Bridge compilation"
    echo ""
    exit 0
fi

# Detect system
detect_system() {
    log_step "Detecting system environment..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        log_error "Cannot detect OS version"
        exit 1
    fi
    
    # Check if WSL
    if grep -q microsoft /proc/version 2>/dev/null; then
        WSL=true
        log_info "Running in WSL environment"
    else
        WSL=false
        log_info "Running in native Linux environment"
    fi
    
    log_info "Detected: $OS $VER"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" = "0" ]; then
        log_warn "Running as root - some operations will be performed system-wide"
        SUDO=""
    else
        log_info "Running as user - will use sudo for system operations"
        SUDO="sudo"
        
        # Check if sudo is available
        if ! command -v sudo &> /dev/null; then
            log_error "sudo is required but not available. Please install sudo or run as root."
            exit 1
        fi
    fi
}

# Update package lists
update_packages() {
    log_step "Updating package lists..."
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] sudo apt-get update -qq"
    else
        $SUDO apt-get update -qq
    fi
}

# Install build dependencies
install_build_deps() {
    log_step "Installing build dependencies..."
    
    # Essential build tools
    BUILD_DEPS=(
        "build-essential"
        "cmake"
        "pkg-config"
        "git"
        "wget"
        "curl"
        "unzip"
        "tar"
    )
    
    # Media Bridge specific dependencies
    NDI_DEPS=(
        "libasound2-dev"  # ALSA development headers for audio output to HDMI (v1.8.4+)
        "libavcodec-dev"
        "libavformat-dev"
        "libavutil-dev"
        "libswscale-dev"
        "libv4l-dev"
        "v4l-utils"
        "libdrm-dev"  # For DRM/KMS display output with hardware scaling (v1.6.8+)
        "libpipewire-0.3-dev"  # For PipeWire audio in ndi-display
    )
    
    # USB creation dependencies
    USB_DEPS=(
        "parted"
        "dosfstools"
        "btrfs-progs"
        "debootstrap"
        "kpartx"
        "util-linux"
        "grub2-common"
        "grub-pc-bin"
        "grub-efi-amd64-bin"
        "grub-efi-amd64"
        "efibootmgr"
        "gdisk"
        "squashfs-tools"
        "systemd-container"
        "arch-install-scripts"
        "qemu-user-static"
        "dos2unix"
    )
    
    # Python testing dependencies
    TEST_DEPS=(
        "python3"
        "python3-pip"
        "python3-venv"
        "sshpass"  # For SSH password authentication in tests
    )
    
    # Time sync dependencies (for PTP support)
    TIME_DEPS=(
        "linuxptp"
        "chrony"
        "ntpdate"
    )
    
    # Combine all dependencies
    ALL_DEPS=("${BUILD_DEPS[@]}" "${NDI_DEPS[@]}" "${USB_DEPS[@]}" "${TEST_DEPS[@]}" "${TIME_DEPS[@]}")
    
    log_info "Installing ${#ALL_DEPS[@]} packages..."
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] sudo apt-get install -y -qq --no-install-recommends ${ALL_DEPS[*]}"
    else
        $SUDO apt-get install -y -qq --no-install-recommends "${ALL_DEPS[@]}"
    fi
    
    log_info "Build dependencies installed successfully"
}

# Download and install NDI SDK
install_ndi_sdk() {
    log_step "Setting up NDI SDK v$NDI_SDK_VERSION..."
    
    # Check if already installed
    if [ -d "$NDI_SDK_DIR" ] && [ -f "$NDI_SDK_DIR/include/Processing.NDI.Lib.h" ]; then
        log_info "NDI SDK already installed, skipping download"
        return 0
    fi
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    log_info "Downloading NDI SDK..."
    wget -q --show-progress "$NDI_SDK_URL" -O ndi_sdk.tar.gz
    
    log_info "Extracting NDI SDK..."
    tar -xzf ndi_sdk.tar.gz
    
    # Find the installer script
    INSTALLER=$(find . -name "Install_NDI_SDK_*.sh" | head -1)
    if [ -z "$INSTALLER" ]; then
        log_error "NDI SDK installer not found in archive"
        exit 1
    fi
    
    # Make installer executable and run it
    chmod +x "$INSTALLER"
    
    # Run installer non-interactively
    log_info "Installing NDI SDK..."
    # The installer extracts to current directory, not home directory
    yes | ./"$INSTALLER" 2>&1 | grep -v "^$"
    
    # Move SDK to project directory
    cd - > /dev/null
    
    # Look for the SDK in temp directory first (where installer extracted it)
    if [ -d "$TEMP_DIR/NDI SDK for Linux" ]; then
        log_info "Moving NDI SDK from temp directory to project root..."
        mv "$TEMP_DIR/NDI SDK for Linux" "./" || cp -r "$TEMP_DIR/NDI SDK for Linux" "./"
        log_info "NDI SDK installed to project directory"
    elif [ -d "$TEMP_DIR/NDI_SDK_Linux" ]; then
        log_info "Moving NDI SDK from temp directory to project root..."
        mv "$TEMP_DIR/NDI_SDK_Linux" "./NDI SDK for Linux" || cp -r "$TEMP_DIR/NDI_SDK_Linux" "./NDI SDK for Linux"
        log_info "NDI SDK installed to project directory"
    elif [ -d ~/NDI\ SDK\ for\ Linux ]; then
        log_info "Moving NDI SDK from home directory to project root..."
        mv ~/NDI\ SDK\ for\ Linux ./ 2>/dev/null || cp -r ~/NDI\ SDK\ for\ Linux ./
        log_info "NDI SDK installed to project directory"
    else
        log_error "NDI SDK installation failed - directory not found in expected locations"
        log_error "Checked: $TEMP_DIR/NDI SDK for Linux, $TEMP_DIR/NDI_SDK_Linux, ~/NDI SDK for Linux"
        exit 1
    fi
    
    # Cleanup
    rm -rf "$TEMP_DIR"
}

# Verify installation
verify_installation() {
    log_step "Verifying installation..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Skipping verification in dry-run mode"
        return 0
    fi
    
    # Check essential tools
    REQUIRED_TOOLS=(
        "cmake"
        "g++"
        "pkg-config"
        "parted"
        "mkfs.fat"
        "mkfs.btrfs"
        "debootstrap"
        "kpartx"
        "grub-install"
    )
    
    MISSING_TOOLS=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            MISSING_TOOLS+=("$tool")
        fi
    done
    
    if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
        log_error "Missing required tools: ${MISSING_TOOLS[*]}"
        exit 1
    fi
    
    # Check NDI SDK
    if [ ! -f "$NDI_SDK_DIR/include/Processing.NDI.Lib.h" ]; then
        log_error "NDI SDK header files not found"
        exit 1
    fi
    
    if [ ! -f "$NDI_SDK_DIR/lib/x86_64-linux-gnu/libndi.so" ]; then
        log_error "NDI SDK library files not found"
        exit 1
    fi
    
    # Check WSL-specific requirements
    if [ "$WSL" = true ]; then
        # Test loop device support
        if ! $SUDO losetup --find &> /dev/null; then
            log_error "Loop device support not available in WSL"
            exit 1
        fi
        
        # Test kpartx
        if ! command -v kpartx &> /dev/null; then
            log_error "kpartx not available - required for WSL USB creation"
            exit 1
        fi
    fi
    
    log_info "All dependencies verified successfully"
}

# Test build
test_build() {
    log_step "Testing Media Bridge compilation..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Skipping build test in dry-run mode"
        return 0
    fi
    
    # Create build directory
    mkdir -p build-test
    cd build-test
    
    # Configure with CMake
    log_info "Configuring build..."
    cmake .. -DCMAKE_BUILD_TYPE=Release > cmake.log 2>&1
    
    # Build
    log_info "Compiling..."
    make -j$(nproc) > make.log 2>&1
    
    # Check if binary was created (binaries are in bin/ subdirectory)
    if [ -f "bin/ndi-capture" ]; then
        log_info "Build test successful - ndi-capture binary created"
        
        # Test binary
        if ./bin/ndi-capture --version > /dev/null 2>&1; then
            log_info "Binary test successful"
        else
            log_warn "Binary created but version test failed"
        fi
    else
        log_error "Build test failed - no binary created"
        echo "CMake log:"
        cat cmake.log
        echo "Make log:"
        cat make.log
        cd ..
        exit 1
    fi
    
    cd ..
    rm -rf build-test
}

# Install Python test dependencies
install_python_test_deps() {
    log_step "Installing Python test dependencies..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Skipping Python package installation in dry-run mode"
        return 0
    fi
    
    # Install pytest and related packages
    log_info "Installing pytest framework and dependencies..."
    pip3 install --user pytest pytest-xdist pytest-timeout testinfra pyyaml python-dotenv pytest-html
    
    # Install as root too for build verification
    $SUDO pip3 install --break-system-packages pytest pytest-xdist pytest-timeout testinfra pyyaml python-dotenv pytest-html 2>/dev/null || true
    
    # Verify installation
    if python3 -m pytest --version > /dev/null 2>&1; then
        log_info "pytest installed successfully"
    else
        log_warn "pytest installation may have issues - check manually"
    fi
    
    log_info "Python test dependencies installed"
}

# Create CLAUDE.md if it doesn't exist
update_claude_md() {
    if [ ! -f "CLAUDE.md" ]; then
        log_step "Creating CLAUDE.md with build instructions..."
        cat > CLAUDE.md << 'EOF'
# Media Bridge - Development Guide

## Quick Setup
Run the environment setup script first:
```bash
./setup-build-environment.sh
```

## Build Commands
```bash
# Standard build
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# USB appliance creation
sudo ./build-image.sh
```

## Environment Requirements
- Ubuntu/Debian (including WSL)
- NDI SDK v6.2.0 (auto-downloaded)
- Build tools (auto-installed)
- USB creation tools (auto-installed)

The setup script handles all dependencies automatically.
EOF
        log_info "CLAUDE.md created"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   Media Bridge Build Environment Setup   ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    detect_system
    check_root
    update_packages
    install_build_deps
    install_ndi_sdk
    install_python_test_deps
    verify_installation
    test_build
    update_claude_md
    
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}         SETUP COMPLETED SUCCESSFULLY   ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    log_info "Environment is ready for Media Bridge development!"
    echo
    echo "Next steps:"
    echo "  1. Build NDI Capture: mkdir build && cd build && cmake .. && make"
    echo "  2. Create USB appliance: sudo ./build-image.sh"
    echo "  3. See CLAUDE.md for more details"
    echo
}

# Run main function
main "$@"