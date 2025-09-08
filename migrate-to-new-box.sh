#!/bin/bash
# Migration script for Media Bridge repository to new development box
# Run this script on the NEW development box at 10.77.9.21

echo "=== Media Bridge Repository Migration Script ==="
echo "This will set up the repository at ~/devel/media-bridge-dev1"
echo

# Create development directory if it doesn't exist
mkdir -p ~/devel

# Navigate to development directory
cd ~/devel

# Remove existing directory if it exists
if [ -d "media-bridge-dev1" ]; then
    echo "Removing existing media-bridge-dev1 directory..."
    rm -rf media-bridge-dev1
fi

# Clone the repository
echo "Cloning repository from GitHub..."
git clone https://github.com/zbynekdrlik/ndi-bridge media-bridge-dev1

# Enter the repository
cd media-bridge-dev1

# Checkout the working branch
echo "Checking out fix-chrome-audio-isolation-issues-34-114 branch..."
git checkout fix-chrome-audio-isolation-issues-34-114

# Show current status
echo
echo "=== Repository Status ==="
git branch --show-current
git log --oneline -5

echo
echo "=== Migration Complete ==="
echo "Repository is now at: ~/devel/media-bridge-dev1"
echo "Current branch: fix-chrome-audio-isolation-issues-34-114"
echo
echo "Latest commits include:"
echo "- Add ALSA device loading to audio manager"
echo "- Document PipeWire 1.4.7 upgrade path for Chrome isolation"
echo "- Replace audio manager with pactl-based version"
echo "- Fix mediabridge user PipeWire runtime and audio manager"
echo
echo "=== Next Steps for New Claude Instance ==="
echo "1. Continue fixing ALL 145+ intercom tests (not just 14)"
echo "2. Run complete audio category tests"
echo "3. Fix all failing tests in both categories"
echo "4. Test device: 10.77.8.119 (or appropriate test box)"
echo
echo "Key fixes already applied:"
echo "- PipeWire filter config disabled (was causing exit 254)"
echo "- Audio manager uses mediabridge user (UID 999)"
echo "- Virtual devices created: intercom-speaker, intercom-microphone"
echo "- test-device.sh always runs with --maxfail=0"
echo
echo "Run tests with:"
echo "  ./tests/test-device.sh 10.77.8.119 tests/component/intercom/"
echo "  ./tests/test-device.sh 10.77.8.119 tests/component/audio/"