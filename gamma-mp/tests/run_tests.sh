#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

LUA="./lua51/lua.exe"

echo "=== GAMMA MP Test Suite ==="
echo

PASS=0
FAIL=0

for f in test_sanity.lua test_loader.lua test_protocol.lua test_alife_guard.lua test_host_events.lua test_client_state.lua test_integration.lua; do
    if [ -f "$f" ]; then
        echo "--- Running $f ---"
        if "$LUA" "$f"; then
            echo "[PASS] $f"
            PASS=$((PASS + 1))
        else
            echo "[FAIL] $f"
            FAIL=$((FAIL + 1))
        fi
        echo
    fi
done

echo "==========================="
echo "Test files passed: $PASS"
echo "Test files failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "OVERALL: FAIL"
    exit 1
else
    echo "OVERALL: PASS"
    exit 0
fi
