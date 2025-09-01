#!/bin/bash
# Run all atomic tests against NDI Bridge device

HOST="${1:-10.77.9.188}"
SSH_KEY="${2:-~/.ssh/ndi_test_key}"

echo "Running NDI Bridge Atomic Test Suite"
echo "====================================="
echo "Target: $HOST"
echo "SSH Key: $SSH_KEY"
echo ""

# Run tests by category
echo "Testing Core Services..."
python3 -m pytest tests/component/core/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "Testing Capture..."
python3 -m pytest tests/component/capture/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "Testing Network..."
python3 -m pytest tests/component/network/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "Testing Display..."
python3 -m pytest tests/component/display/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "Testing Audio..."
python3 -m pytest tests/component/audio/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "Testing Web Interface..."
python3 -m pytest tests/component/web/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "Testing Helpers..."
python3 -m pytest tests/component/helpers/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "Testing Time Sync..."
python3 -m pytest tests/component/timesync/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "Testing System Resources..."
python3 -m pytest tests/system/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "Testing Integration..."
python3 -m pytest tests/integration/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no

echo ""
echo "=================================="
echo "Running full summary report..."
python3 -m pytest tests/ --host "$HOST" --ssh-key "$SSH_KEY" -q --tb=no --co | grep "test session starts\|collected"