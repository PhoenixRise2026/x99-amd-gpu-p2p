#!/usr/bin/env bash
#
# check-dma-addresses.sh - Inspects DMA masks and IOMMU domain configurations
#
set -euo pipefail

echo "=== DMA Masks & IOMMU Domain Assessment ==="
echo "Kernel cmdline: $(cat /proc/cmdline)"
echo

for dev in $(lspci -D -d 1002:7551 | awk '{print $1}'); do
    SYS_PATH="/sys/bus/pci/devices/${dev}"
    echo "--- Device $dev ---"
    if [[ -d "$SYS_PATH" ]]; then
        echo "  dma_mask_bits:            $(cat "${SYS_PATH}/dma_mask_bits" 2>/dev/null || echo "Unknown")"
        echo "  consistent_dma_mask_bits: $(cat "${SYS_PATH}/consistent_dma_mask_bits" 2>/dev/null || echo "Unknown")"
        IOMMU_GRP=$(readlink "${SYS_PATH}/iommu_group" 2>/dev/null || echo "None")
        echo "  iommu_group:              $(basename "$IOMMU_GRP")"
    fi
    echo
done

echo "--- IOMMU Operating Mode ---"
if grep -q "Default domain type: Translated" /var/log/dmesg 2>/dev/null || journalctl -k -b 0 2>/dev/null | grep -q "Default domain type: Translated"; then
    echo "  Status: Intel VT-d Translated (DMA-FQ) Active"
    echo "  Note:   IOVA allocations fit within standard 32/44-bit DMA space."
else
    echo "  Status: Check dmesg for IOMMU domain type."
fi
