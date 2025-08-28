#!/bin/bash
# Chrome and dependencies are pre-installed during image build
# This script is kept for compatibility but is no longer needed

echo "Chrome and dependencies are already installed during image build"
echo "The VDO.Ninja intercom service is ready to use"
echo ""
echo "To check status: systemctl status vdo-ninja-intercom"
echo "To view logs: journalctl -u vdo-ninja-intercom -f"
echo ""
echo "Service should already be running. If not:"
echo "  systemctl start vdo-ninja-intercom"