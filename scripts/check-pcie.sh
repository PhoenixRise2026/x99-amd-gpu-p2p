#!/usr/bin/env bash
#
# check-pcie.sh - Inspects PCIe link speed, width, and BAR configurations
#
set -euo pipefail

echo "=== GPU PCIe Link & BAR Status ==="
for dev in $(lspci -D -d 1002:7551 | awk '{print $1}'); do
    echo "--- Device $dev ---"
    SYS_PATH="/sys/bus/pci/devices/${dev}"
    if [[ -d "$SYS_PATH" ]]; then
        echo "  Current Speed: $(cat "${SYS_PATH}/current_link_speed" 2>/dev/null || echo "Unknown")"
        echo "  Current Width: x$(cat "${SYS_PATH}/current_link_width" 2>/dev/null || echo "Unknown")"
        echo "  Max Speed:     $(cat "${SYS_PATH}/max_link_speed" 2>/dev/null || echo "Unknown")"
        echo "  Max Width:     x$(cat "${SYS_PATH}/max_link_width" 2>/dev/null || echo "Unknown")"
    fi
    lspci -v -s "$dev" | grep -E "Region|Memory at" || true
    echo
done
