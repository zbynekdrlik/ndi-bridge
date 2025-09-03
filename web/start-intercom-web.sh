#!/bin/bash
# Start Media Bridge Intercom Web Interface
# This replaces the old Python API server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Starting Media Bridge Intercom Web Interface..."

# Check if FastAPI is installed
if ! python3 -c "import fastapi" 2>/dev/null; then
    echo "Installing dependencies..."
    pip3 install -r web/backend/requirements.txt
fi

# Kill any existing instance
pkill -f "uvicorn.*main:app" || true

# Start FastAPI backend
cd web/backend
echo "Starting FastAPI backend on port 8000..."
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload &

echo ""
echo "========================================="
echo "Media Bridge Intercom Web Interface Started"
echo "========================================="
echo ""
echo "Access the interface at:"
echo "  http://$(hostname -I | awk '{print $1}'):8000"
echo "  http://$(hostname).local:8000"
echo ""
echo "The interface is mobile-optimized with:"
echo "  - Large MIC MUTE button (primary control)"
echo "  - Headphone volume control"
echo "  - Microphone gain adjustment"
echo "  - Live audio level meters"
echo "  - Save as default settings"
echo ""
echo "To stop: pkill -f 'uvicorn.*main:app'"
echo ""