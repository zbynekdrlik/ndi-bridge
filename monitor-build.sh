#!/bin/bash
# Monitor v2.4.5 build progress

LOG="build-v2.4.5.log"

echo "Monitoring build progress..."
echo "================================"

while true; do
    if grep -q "MODULE 07" "$LOG" 2>/dev/null; then
        echo "✓ MODULE 07 (Base Setup) started"
        if grep -q "Creating mediabridge user" "$LOG"; then
            echo "  ✓ Creating mediabridge user"
            grep "mediabridge" "$LOG" | tail -5
        fi
    fi
    
    if grep -q "MODULE 10a" "$LOG" 2>/dev/null; then
        echo "✓ MODULE 10a (PipeWire) started"
    fi
    
    if grep -q "MODULE 11" "$LOG" 2>/dev/null; then
        echo "✓ MODULE 11 (Intercom Chrome) started"
        if grep -q "chown.*mediabridge:mediabridge" "$LOG"; then
            echo "  ✓ chown operations found"
        fi
    fi
    
    if grep -q "MODULE 13" "$LOG" 2>/dev/null; then
        echo "✓ MODULE 13 (Filesystem Config) started"
        if grep -q "grub-install" "$LOG"; then
            echo "  ✓ GRUB installation started"
        fi
    fi
    
    if grep -q "BUILD SUCCESSFUL\|BUILD FAILED" "$LOG" 2>/dev/null; then
        echo "================================"
        tail -5 "$LOG"
        break
    fi
    
    sleep 30
    echo -n "."
done