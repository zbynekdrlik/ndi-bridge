#!/bin/bash
# Pre-compile Inferno and Statime for NDI Bridge
# This avoids long compilation during image build

SCRIPT_DIR="$(dirname "$0")"
BUILD_DIR="$SCRIPT_DIR/../build"
INFERNO_DIR="$BUILD_DIR/inferno"
STATIME_DIR="$BUILD_DIR/statime"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Pre-compiling Inferno and Statime for Dante audio support${NC}"

# Install Rust from Ubuntu repos (much faster than rustup)
echo "Checking Rust installation..."
if ! command -v cargo >/dev/null 2>&1; then
    echo "Installing Rust 1.82 from Ubuntu repositories..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq rustc-1.82 cargo-1.82 pkg-config libasound2-dev build-essential git
    
    # Create symlinks for default cargo/rustc
    sudo update-alternatives --install /usr/bin/cargo cargo /usr/bin/cargo-1.82 100
    sudo update-alternatives --install /usr/bin/rustc rustc /usr/bin/rustc-1.82 100
fi

RUST_VERSION=$(rustc --version | cut -d' ' -f2)
echo "Using Rust version: $RUST_VERSION"

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Compile Inferno
echo -e "${YELLOW}Compiling Inferno (this will take 5-10 minutes)...${NC}"
if [ ! -d "$INFERNO_DIR" ]; then
    git clone --recurse-submodules https://gitlab.com/lumifaza/inferno.git
fi

cd "$INFERNO_DIR" || { echo "Failed to enter Inferno directory"; exit 1; }
git pull
git submodule update --init --recursive

# Remove lock file to avoid version conflicts  
rm -f Cargo.lock

# Build Inferno
cargo build --release 2>&1 | tail -20

if [ -f "target/release/libasound_module_pcm_inferno.so" ]; then
    echo -e "${GREEN}✓ Inferno ALSA plugin compiled successfully${NC}"
else
    echo -e "${RED}✗ Inferno compilation failed${NC}"
    exit 1
fi

# Compile Statime
echo -e "${YELLOW}Compiling Statime PTP daemon...${NC}"
cd "$BUILD_DIR"

if [ ! -d "$STATIME_DIR" ]; then
    git clone --recurse-submodules -b inferno-dev https://github.com/teodly/statime.git
fi

cd "$STATIME_DIR"
git pull
cargo build --release 2>&1 | tail -20

if [ -f "target/release/statime" ]; then
    echo -e "${GREEN}✓ Statime compiled successfully${NC}"
else
    echo -e "${RED}✗ Statime compilation failed${NC}"
    exit 1
fi

# Create binary package directory
DANTE_PKG_DIR="$BUILD_DIR/dante-package"
mkdir -p "$DANTE_PKG_DIR/lib"
mkdir -p "$DANTE_PKG_DIR/bin"
mkdir -p "$DANTE_PKG_DIR/config"

# Copy compiled binaries
echo "Packaging Dante binaries..."
cp "$INFERNO_DIR/target/release/libasound_module_pcm_inferno.so" "$DANTE_PKG_DIR/lib/"
cp "$INFERNO_DIR/target/release/inferno2pipe" "$DANTE_PKG_DIR/bin/" 2>/dev/null || true
cp "$STATIME_DIR/target/release/statime" "$DANTE_PKG_DIR/bin/"
cp "$STATIME_DIR/inferno-ptpv1.toml" "$DANTE_PKG_DIR/config/statime.conf"

# Update statime config for br0
sed -i 's/interface = ".*"/interface = "br0"/' "$DANTE_PKG_DIR/config/statime.conf"

echo -e "${GREEN}Pre-compilation complete!${NC}"
echo "Binaries packaged in: $DANTE_PKG_DIR"
echo
echo "Files ready for image build:"
ls -la "$DANTE_PKG_DIR/lib/"
ls -la "$DANTE_PKG_DIR/bin/"
echo
echo -e "${GREEN}These binaries will be copied during image build (no compilation needed)${NC}"