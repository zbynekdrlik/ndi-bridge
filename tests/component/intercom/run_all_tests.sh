#!/bin/bash
# Run all intercom tests with proper isolation and order

HOST="${1:-10.77.8.119}"
SSH_KEY="${2:-$HOME/.ssh/ndi_test_key}"

echo "===== INTERCOM TEST SUITE ====="
echo "Host: $HOST"
echo ""

TOTAL_PASS=0
TOTAL_FAIL=0

# Run non-restart tests first
echo "=== Phase 1: Running non-restart tests ==="
python3 -m pytest tests/component/intercom/ \
    --host "$HOST" \
    --ssh-key "$SSH_KEY" \
    --tb=no \
    --timeout=60 \
    -k "not restart" \
    -q 2>&1 | tee /tmp/test_phase1.log

# Extract results
PHASE1_RESULT=$(tail -1 /tmp/test_phase1.log)
echo "$PHASE1_RESULT"

# Run restart tests separately with longer timeout
echo ""
echo "=== Phase 2: Running service restart tests ==="
python3 -m pytest tests/component/intercom/ \
    --host "$HOST" \
    --ssh-key "$SSH_KEY" \
    --tb=no \
    --timeout=120 \
    -k "restart" \
    -q 2>&1 | tee /tmp/test_phase2.log

# Extract results  
PHASE2_RESULT=$(tail -1 /tmp/test_phase2.log)
echo "$PHASE2_RESULT"

echo ""
echo "===== FINAL SUMMARY ====="
echo "Phase 1 (non-restart): $PHASE1_RESULT"
echo "Phase 2 (restart tests): $PHASE2_RESULT"

# Parse and combine results
PASS1=$(echo "$PHASE1_RESULT" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+")
PASS2=$(echo "$PHASE2_RESULT" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+")
FAIL1=$(echo "$PHASE1_RESULT" | grep -oE "[0-9]+ failed" | grep -oE "[0-9]+")
FAIL2=$(echo "$PHASE2_RESULT" | grep -oE "[0-9]+ failed" | grep -oE "[0-9]+")

TOTAL_PASS=$((${PASS1:-0} + ${PASS2:-0}))
TOTAL_FAIL=$((${FAIL1:-0} + ${FAIL2:-0}))

echo ""
echo "TOTAL: $TOTAL_PASS passed, $TOTAL_FAIL failed"

if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "✅ ALL TESTS PASSED!"
    exit 0
else
    echo "❌ $TOTAL_FAIL tests failed"
    exit 1
fi