#!/usr/bin/env bash
#
# diagnose.sh - Read-only platform and P2PDMA diagnostic check (Fail-Closed Architecture)
#
# Usage:
#   ./diagnose.sh         # Quick read-only platform prerequisites check (defaults to INCONCLUSIVE for P2P readiness)
#   ./diagnose.sh --full  # Run full active peer transfer validation and error inspection
#
set -euo pipefail

FULL_MODE=0
if [[ "${1:-}" == "--full" ]]; then
    FULL_MODE=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREREQS_PASS=1

echo "=========================================="
echo "=== AMD GPU P2P Platform Check ==="
echo "=========================================="
echo

# 1. CPU Check
echo "--- 1. CPU & Socket Topology ---"
CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || true)
SOCKETS=$(lscpu 2>/dev/null | grep "Socket(s):" | awk '{print $2}' || true)
echo "  Model:    ${CPU_MODEL:-Unknown}"
echo "  Sockets:  ${SOCKETS:-Unknown}"
if [[ "$CPU_MODEL" =~ "Xeon" && "$SOCKETS" == "1" ]]; then
    echo "  Status:   PASS (Single-socket Xeon identified)"
else
    echo "  Status:   INFO (Check topology for multi-socket NUMA/QPI constraints)"
fi
echo

# 2. Host Bridge Check
echo "--- 2. Host Bridge & Root Complex ---"
HB_DEV=$(lspci -d 8086:6f00 2>/dev/null | head -n1 || true)
if [[ -n "$HB_DEV" ]]; then
    echo "  Device:   8086:6f00 (Intel Broadwell-EP Host Bridge)"
    echo "  Role:     Host Bridge / DMI2 (devfn 00.0)"
    echo "  Status:   PASS"
else
    OTHER_HB=$(lspci -d 8086:* 2>/dev/null | grep -i "host bridge" | head -n1 || true)
    echo "  Device:   ${OTHER_HB:-None detected}"
    echo "  Status:   WARN (Target 8086:6f00 not matched; verify if host bridge supports P2PDMA)"
    PREREQS_PASS=0
fi
echo

# 3. PCIe Topology and Endpoints
echo "--- 3. GPUs & Root Ports ---"
GPU_COUNT=0
GPUS=()
while read -r line; do
    [[ -z "$line" ]] && continue
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
    echo "  Status:   FAIL (Found $GPU_COUNT AMD R9700 GPUs; dual GPU required for P2P)"
    PREREQS_PASS=0
else
    echo "  Status:   PASS ($GPU_COUNT AMD R9700 GPUs detected)"
fi
echo

# 4. Topology Domain Assessment
echo "--- 4. Topology Relationship ---"
ROOT_PORTS_DISTINCT=0
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
        echo "  Relationship:            DIFFERENT_ROOT_PORTS (P2P must route through Host Bridge)"
        ROOT_PORTS_DISTINCT=1
    else
        echo "  Relationship:            SAME_ROOT_PORT"
    fi
fi
echo

# 5. DMA Mask and IOMMU
echo "--- 5. DMA Mask & IOMMU ---"
IOMMU_TRANSLATED=0
if grep -q "Default domain type: Translated" /var/log/dmesg 2>/dev/null || journalctl -k -b 0 2>/dev/null | grep -q "Default domain type: Translated"; then
    IOMMU_TRANSLATED=1
    echo "  IOMMU:        Intel VT-d Translated (DMA-FQ)"
elif grep -q "iommu=pt" /proc/cmdline 2>/dev/null; then
    echo "  IOMMU:        Passthrough (iommu=pt active)"
else
    echo "  IOMMU:        Translated / Standard (iommu=pt absent)"
    IOMMU_TRANSLATED=1
fi

if [[ $IOMMU_TRANSLATED -eq 1 ]]; then
    echo "  Status:       PASS"
else
    echo "  Status:       WARN (Passthrough mode may expose physical addresses >44-bit)"
    PREREQS_PASS=0
fi

for BDF in "${GPUS[@]}"; do
    MASK=$(cat "/sys/bus/pci/devices/${BDF}/dma_mask_bits" 2>/dev/null || echo "Unknown")
    echo "  GPU $BDF DMA mask: $MASK-bit"
done
echo

# 6. Kernel & P2PDMA Whitelist Check
echo "--- 6. Kernel & P2PDMA Whitelist Detection ---"
KERNEL_VER=$(uname -r)
echo "  Running Kernel: $KERNEL_VER"
WHITELIST_STATUS="UNKNOWN"
if [[ -f "/sys/kernel/debug/pci_p2pdma" ]]; then
    if grep -q "8086:6f00" /sys/kernel/debug/pci_p2pdma 2>/dev/null; then
        WHITELIST_STATUS="PRESENT"
    else
        WHITELIST_STATUS="ABSENT"
    fi
fi
echo "  KERNEL_6F00_WHITELIST: $WHITELIST_STATUS"
if [[ "$WHITELIST_STATUS" == "ABSENT" ]]; then
    echo "  Status:                FAIL (8086:6f00 explicitly absent in kernel debugfs)"
    PREREQS_PASS=0
elif [[ "$WHITELIST_STATUS" == "PRESENT" ]]; then
    echo "  Status:                PASS (Verified via kernel debugfs)"
else
    echo "  Status:                INFO (Debugfs not available; functional test required to confirm)"
fi
echo

# 7. Initial Kernel Error Counters
echo "--- 7. Kernel Error Counters ---"
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
if [[ $DMAR_FAULTS -eq 0 && $AER_ERRORS -eq 0 && $RESETS -eq 0 ]]; then
    echo "  Status:       PASS (Clean kernel log)"
else
    echo "  Status:       FAIL (Prior bus errors or resets detected)"
    PREREQS_PASS=0
fi
echo

# ==============================================================================
# DEFAULT MODE VERDICT (Prerequisites Only)
# ==============================================================================
if [[ $FULL_MODE -eq 0 ]]; then
    echo "=========================================="
    echo "=== Summary Verdict (Prerequisites Mode) ==="
    echo "=========================================="
    if [[ $PREREQS_PASS -eq 1 ]]; then
        echo "P2P_PREREQUISITES = PASS"
        echo "DIRECT_P2P_READY = INCONCLUSIVE"
        echo "Note: Prerequisites are satisfied, but active peer transfers have"
        echo "      not been executed in default mode. Run './diagnose.sh --full'"
        echo "      to run active peer benchmarks and confirm end-to-end readiness."
    else
        echo "P2P_PREREQUISITES = FAIL"
        echo "DIRECT_P2P_READY = NO"
    fi
    echo "=========================================="
    exit 0
fi

# ==============================================================================
# FULL MODE: Active Peer Benchmark Verification
# ==============================================================================
echo "=========================================="
echo "=== Full Mode: Active Peer Validation ==="
echo "=========================================="
echo

HIP_IPC_RESULT="SKIP"
TB_RESULT="SKIP"
RCCL_RESULT="SKIP"

# Allow test harness injection for unit testing
if [[ -n "${TEST_MOCK_HIP_IPC:-}" ]]; then
    HIP_IPC_RESULT="$TEST_MOCK_HIP_IPC"
    echo "  [TEST MOCK] HIP IPC Result: $HIP_IPC_RESULT"
else
    echo "--- A. HIP IPC Validation ---"
    if [[ -x "${SCRIPT_DIR}/check-hip-ipc.sh" ]]; then
        set +e
        "${SCRIPT_DIR}/check-hip-ipc.sh"
        IPC_RET=$?
        set -e
        if [[ $IPC_RET -eq 0 ]]; then
            HIP_IPC_RESULT="PASS"
        elif [[ $IPC_RET -eq 2 ]]; then
            HIP_IPC_RESULT="SKIP"
        else
            HIP_IPC_RESULT="FAIL"
        fi
    else
        echo "  check-hip-ipc.sh not found."
    fi
fi
echo "  HIP_IPC: $HIP_IPC_RESULT"
echo

if [[ -n "${TEST_MOCK_TRANSFERBENCH:-}" ]]; then
    TB_RESULT="$TEST_MOCK_TRANSFERBENCH"
    echo "  [TEST MOCK] TransferBench Result: $TB_RESULT"
else
    echo "--- B. TransferBench P2P Bandwidth Validation ---"
    TB_BIN=""
    for tb_cand in /opt/rocm/bin/TransferBench ./bin/TransferBench; do
        if [[ -x "$tb_cand" ]]; then
            TB_BIN="$tb_cand"
            break
        fi
    done
    if [[ -n "$TB_BIN" ]]; then
        set +e
        TB_OUT=$("$TB_BIN" p2p 2>&1)
        TB_RET=$?
        set -e
        if [[ $TB_RET -eq 0 ]]; then
            TB_RESULT="PASS"
            echo "  TransferBench execution: PASS"
        else
            TB_RESULT="FAIL"
            echo "  TransferBench execution: FAIL"
        fi
    else
        echo "  [SKIP] TransferBench binary not found at default paths."
        TB_RESULT="SKIP"
    fi
fi
echo "  TRANSFERBENCH_DIRECT_PEER: $TB_RESULT"
echo

if [[ -n "${TEST_MOCK_RCCL:-}" ]]; then
    RCCL_RESULT="$TEST_MOCK_RCCL"
    echo "  [TEST MOCK] RCCL Result: $RCCL_RESULT"
else
    echo "--- C. RCCL Collective Acceleration Validation ---"
    RCCL_TEST_BIN=""
    for rccl_cand in /opt/rocm/bin/all_reduce_perf ./bin/all_reduce_perf; do
        if [[ -x "$rccl_cand" ]]; then
            RCCL_TEST_BIN="$rccl_cand"
            break
        fi
    done
    if [[ -n "$RCCL_TEST_BIN" ]]; then
        set +e
        export NCCL_P2P_LEVEL=PHB
        RCCL_OUT=$("$RCCL_TEST_BIN" -b 64M -e 64M -g 2 2>&1)
        RCCL_RET=$?
        set -e
        if [[ $RCCL_RET -eq 0 ]] && ! echo "$RCCL_OUT" | grep -q "SHM"; then
            RCCL_RESULT="PASS"
            echo "  RCCL P2P AllReduce: PASS"
        else
            RCCL_RESULT="FAIL"
            echo "  RCCL P2P AllReduce: FAIL"
        fi
    else
        echo "  [SKIP] rccl-tests binary not found at default paths."
        RCCL_RESULT="SKIP"
    fi
fi
echo "  RCCL_DIRECT_P2P: $RCCL_RESULT"
echo

# Post-test kernel health re-check
echo "--- Post-Test Kernel Health Audit ---"
POST_DMAR=0
POST_AER=0
POST_RESETS=0
if command -v journalctl >/dev/null 2>&1; then
    POST_DMAR=$(journalctl -k -b 0 2>/dev/null | grep -ciE "DMAR:.*fault" || true)
    POST_AER=$(journalctl -k -b 0 2>/dev/null | grep -ciE "AER:.*error" || true)
    POST_RESETS=$(journalctl -k -b 0 2>/dev/null | grep -ciE "amdgpu:.*gpu reset" || true)
fi
NEW_DMAR=$((POST_DMAR - DMAR_FAULTS))
NEW_AER=$((POST_AER - AER_ERRORS))
NEW_RESETS=$((POST_RESETS - RESETS))
echo "  New DMAR Faults: $NEW_DMAR"
echo "  New AER Errors:  $NEW_AER"
echo "  New GPU Resets:  $NEW_RESETS"
echo

echo "=========================================="
echo "=== Final Full Mode Verdict ==="
echo "=========================================="
if [[ $PREREQS_PASS -eq 0 || "$HIP_IPC_RESULT" == "FAIL" || "$TB_RESULT" == "FAIL" || "$RCCL_RESULT" == "FAIL" || $NEW_DMAR -gt 0 || $NEW_AER -gt 0 || $NEW_RESETS -gt 0 ]]; then
    echo "P2P_PREREQUISITES = $([[ $PREREQS_PASS -eq 1 ]] && echo PASS || echo FAIL)"
    echo "DIRECT_P2P_READY = NO"
elif [[ "$HIP_IPC_RESULT" == "SKIP" || "$TB_RESULT" == "SKIP" || "$RCCL_RESULT" == "SKIP" ]]; then
    echo "P2P_PREREQUISITES = PASS"
    echo "DIRECT_P2P_READY = INCONCLUSIVE"
    echo "Reason: One or more active benchmark tools were skipped (missing binary)."
elif [[ "$HIP_IPC_RESULT" == "PASS" && "$TB_RESULT" == "PASS" && "$RCCL_RESULT" == "PASS" && $NEW_DMAR -eq 0 && $NEW_AER -eq 0 && $NEW_RESETS -eq 0 ]]; then
    echo "P2P_PREREQUISITES = PASS"
    echo "DIRECT_P2P_READY = YES"
    echo "All peer verification tests passed cleanly with 0 kernel errors."
else
    echo "DIRECT_P2P_READY = INCONCLUSIVE"
fi
echo "=========================================="
