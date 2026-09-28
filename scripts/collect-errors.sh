#!/usr/bin/env bash
#
# collect-errors.sh - Read-only audit of kernel journal for AER, DMAR, and GPU errors
#
set -euo pipefail

echo "=== Kernel Health & Error Audit ==="

if ! command -v journalctl >/dev/null 2>&1; then
    echo "journalctl not available."
    exit 0
fi

echo "--- DMAR Faults ---"
journalctl -k -b 0 2>/dev/null | grep -iE "DMAR:.*fault" || echo "Zero DMAR faults found."

echo
echo "--- PCIe AER Errors ---"
journalctl -k -b 0 2>/dev/null | grep -iE "AER:.*error" || echo "Zero PCIe AER errors found."

echo
echo "--- AMDGPU GPU Resets & Ring Timeouts ---"
journalctl -k -b 0 2>/dev/null | grep -iE "amdgpu:.*gpu reset|ring.*timeout" || echo "Zero GPU resets or ring timeouts found."

echo
echo "Kernel Error Audit Complete."
