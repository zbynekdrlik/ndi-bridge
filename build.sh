#!/bin/bash
# Helper script for building NDI Bridge components
# This ensures builds are always done from the correct directory

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory (repository root)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$REPO_ROOT/build"

# Function to print colored messages
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create build directory if it doesn't exist
if [ ! -d "$BUILD_DIR" ]; then
    log_info "Creating build directory at $BUILD_DIR"
    mkdir -p "$BUILD_DIR"
fi

# Check if cmake has been run
if [ ! -f "$BUILD_DIR/Makefile" ]; then
    log_error "Build not configured. Running cmake..."
    cd "$BUILD_DIR"
    cmake ..
    if [ $? -ne 0 ]; then
        log_error "CMake configuration failed"
        exit 1
    fi
fi

# Parse arguments
TARGET=""
CLEAN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [target] [options]"
            echo ""
            echo "Targets:"
            echo "  ndi-capture   - Build capture component only"
            echo "  ndi-display   - Build display component only"
            echo "  all           - Build everything (default)"
            echo ""
            echo "Options:"
            echo "  --clean       - Clean before building"
            echo "  --verbose     - Verbose build output"
            echo "  --help        - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                    # Build everything"
            echo "  $0 ndi-display        # Build display component only"
            echo "  $0 --clean            # Clean and rebuild everything"
            echo "  $0 ndi-display --clean # Clean and rebuild display only"
            exit 0
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

# Default to building everything
if [ -z "$TARGET" ]; then
    TARGET="all"
fi

# Change to build directory
cd "$BUILD_DIR"
log_info "Building in: $BUILD_DIR"

# Clean if requested
if [ "$CLEAN" = true ]; then
    log_info "Cleaning build directory..."
    if [ "$TARGET" = "all" ]; then
        make clean 2>/dev/null || rm -rf CMakeFiles bin lib
    else
        rm -f "bin/$TARGET" 2>/dev/null || true
    fi
fi

# Determine number of cores
CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
log_info "Building with $CORES parallel jobs"

# Build
log_info "Building target: $TARGET"
if [ "$VERBOSE" = true ]; then
    make "$TARGET" -j"$CORES" VERBOSE=1
else
    make "$TARGET" -j"$CORES"
fi

# Check result
if [ $? -eq 0 ]; then
    log_info "Build successful!"
    
    # Show output location
    if [ "$TARGET" != "all" ] && [ -f "bin/$TARGET" ]; then
        SIZE=$(ls -lh "bin/$TARGET" | awk '{print $5}')
        log_info "Output: $BUILD_DIR/bin/$TARGET ($SIZE)"
    else
        log_info "Binaries in: $BUILD_DIR/bin/"
        ls -lh bin/ 2>/dev/null | grep -E "ndi-" || true
    fi
else
    log_error "Build failed!"
    exit 1
fi