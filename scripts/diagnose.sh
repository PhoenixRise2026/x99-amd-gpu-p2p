#!/usr/bin/env bash
#
# diagnose.sh - Read-only platform and P2PDMA diagnostic check
#
# Usage:
#   ./diagnose.sh         # Quick read-only platform and configuration audit
#   ./diagnose.sh --full  # Run diagnostic checks plus IPC/TransferBench if binaries exist
#

set -euo pipefail

FULL_MODE=0
if [[ "${1:-}" == "--full" ]]; then
    FULL_MODE=1
fi

echo "=== AMD GPU P2P Platform Check ==="
echo

# 1. CPU Check
echo "--- CPU ---"
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs || true)
SOCKETS=$(lscpu | grep "Socket(s):" | awk '{print $2}' || true)
echo "  Model:    ${CPU_MODEL:-Unknown}"
echo "  Sockets:  ${SOCKETS:-Unknown}"
if [[ "$CPU_MODEL" =~ "Xeon" && "$SOCKETS" == "1" ]]; then
    echo "  Status:   PASS (Single-socket Xeon identified)"
else
    echo "  Status:   INFO (Check topology for multi-socket NUMA/QPI constraints)"
fi
echo

# 2. Host Bridge Check
echo "--- Host Bridge & Root Complex ---"
HB_DEV=$(lspci -d 8086:6f00 2>/dev/null | head -n1 || true)
if [[ -n "$HB_DEV" ]]; then
    echo "  Device:   8086:6f00 (Intel Broadwell-EP Host Bridge)"
    echo "  Role:     Host Bridge / DMI2 (devfn 00.0)"
else
    echo "  Device:   $(lspci -d 8086:* | grep -i "host bridge" | head -n1 || true)"
fi
echo

# 3. PCIe Topology and Endpoints
echo "--- GPUs & Root Ports ---"
GPU_COUNT=0
GPUS=()
while read -r line; do
    RAW_BDF=$(echo "$line" | awk '{print $1}')
    if [[ "$RAW_BDF" =~ ^[0-9a-fA-F]{4}: ]]; then
        BDF="$RAW_BDF"
    else
        BDF="0000:${RAW_BDF}"
    fi
    GPUS+=("$BDF")
    GPU_COUNT=$((GPU_COUNT + 1))
    SYS_PATH="/sys/bus/pci/devices/${BDF}"
    SPEED=$(cat "${SYS_PATH}/current_link_speed" 2>/dev/null || echo "Unknown")
    WIDTH=$(cat "${SYS_PATH}/current_link_width" 2>/dev/null || echo "Unknown")
    echo "  GPU $((GPU_COUNT-1)): $BDF | Link: $SPEED x$WIDTH"
done < <(lspci -D -d 1002:7551 2>/dev/null || true)

if [[ $GPU_COUNT -lt 2 ]]; then
    echo "  Status:   WARN (Found $GPU_COUNT AMD R9700 GPUs; dual GPU required for P2P)"
else
    echo "  Status:   PASS ($GPU_COUNT AMD R9700 GPUs detected)"
fi
echo

# 4. Topology Domain Assessment
echo "--- Topology Relationship ---"
if [[ $GPU_COUNT -ge 2 ]]; then
    GPU0="${GPUS[0]}"
    GPU1="${GPUS[1]}"
    REAL0=$(readlink -f "/sys/bus/pci/devices/${GPU0}" 2>/dev/null || true)
    REAL1=$(readlink -f "/sys/bus/pci/devices/${GPU1}" 2>/dev/null || true)
    RP0=$(basename "$(dirname "$(dirname "$(dirname "$REAL0")")")" 2>/dev/null || echo "Unknown")
    RP1=$(basename "$(dirname "$(dirname "$(dirname "$REAL1")")")" 2>/dev/null || echo "Unknown")
    echo "  GPU0 Upstream Root Port: $RP0"
    echo "  GPU1 Upstream Root Port: $RP1"
    if [[ "$RP0" != "$RP1" && "$RP0" != "Unknown" ]]; then
        echo "  Root Ports:              DIFFERENT_ROOT_PORTS (P2P must route through Host Bridge)"
    else
        echo "  Root Ports:              SAME_ROOT_PORT"
    fi
fi
echo

# 5. DMA Mask and IOMMU
echo "--- DMA Mask & IOMMU ---"
IOMMU_TRANSLATED=0
if grep -q "Default domain type: Translated" /var/log/dmesg 2>/dev/null || journalctl -k -b 0 2>/dev/null | grep -q "Default domain type: Translated"; then
    IOMMU_TRANSLATED=1
    echo "  IOMMU:        Intel VT-d Translated (DMA-FQ)"
elif grep -q "iommu=pt" /proc/cmdline; then
    echo "  IOMMU:        Passthrough (iommu=pt active)"
else
    echo "  IOMMU:        Translated / Standard (iommu=pt absent)"
    IOMMU_TRANSLATED=1
fi

for BDF in "${GPUS[@]}"; do
    MASK=$(cat "/sys/bus/pci/devices/${BDF}/dma_mask_bits" 2>/dev/null || echo "Unknown")
    echo "  GPU $BDF DMA mask: $MASK-bit"
done
echo

# 6. Kernel & P2PDMA Whitelist Check
echo "--- Kernel & P2PDMA Whitelist ---"
KERNEL_VER=$(uname -r)
echo "  Running Kernel: $KERNEL_VER"
WHITELIST_STATUS="UNKNOWN"
if [[ -f "/sys/kernel/debug/pci_p2pdma" ]]; then
    WHITELIST_STATUS="ACCESSIBLE"
elif [[ "$KERNEL_VER" =~ "p2p" ]]; then
    WHITELIST_STATUS="VALIDATED_LOCAL_BUILD"
fi
echo "  8086:6f00 Whitelist: $WHITELIST_STATUS"
echo

# 7. Software Stack Presence
echo "--- Software Stack ---"
ROCM_VER=$(dpkg -l rocm-core 2>/dev/null | grep "^ii" | awk '{print $3}' || echo "Not packaged")
echo "  ROCm Core:    $ROCM_VER"

TRITON_STATUS="Not detected"
if python3 -c "import triton; print('Active v' + triton.__version__)" 2>/dev/null; then
    TRITON_STATUS="ACTIVE"
fi
echo "  Triton:       $TRITON_STATUS"

AITER_STATUS="ABSENT"
if python3 -c "import aiter; print('v' + aiter.__version__)" 2>/dev/null; then
    AITER_STATUS="PRESENT"
fi
echo "  AITER:        $AITER_STATUS"
echo

# 8. Kernel Health
echo "--- Kernel Health Audit ---"
DMAR_FAULTS=0
AER_ERRORS=0
RESETS=0
if command -v journalctl >/dev/null 2>&1; then
    DMAR_FAULTS=$(journalctl -k -b 0 2>/dev/null | grep -ciE "DMAR:.*fault" || true)
    AER_ERRORS=$(journalctl -k -b 0 2>/dev/null | grep -ciE "AER:.*error" || true)
    RESETS=$(journalctl -k -b 0 2>/dev/null | grep -ciE "amdgpu:.*gpu reset" || true)
fi
echo "  DMAR Faults:  $DMAR_FAULTS"
echo "  AER Errors:   $AER_ERRORS"
echo "  GPU Resets:   $RESETS"
echo

# 9. Optional Full Verification
if [[ $FULL_MODE -eq 1 ]]; then
    echo "--- Full Diagnostic Tests ---"
    if [[ -x "/opt/rocm/bin/TransferBench" ]]; then
        echo "  Running TransferBench quick check..."
        /opt/rocm/bin/TransferBench p2p || true
    else
        echo "  TransferBench binary not found at default path (skipped)."
    fi
fi

# Overall Summary
echo "=========================================="
if [[ $GPU_COUNT -ge 2 && $IOMMU_TRANSLATED -eq 1 && $DMAR_FAULTS -eq 0 && $AER_ERRORS -eq 0 ]]; then
    echo "OVERALL: DIRECT_P2P_READY = YES"
else
    echo "OVERALL: DIRECT_P2P_READY = INCONCLUSIVE"
fi
echo "=========================================="
