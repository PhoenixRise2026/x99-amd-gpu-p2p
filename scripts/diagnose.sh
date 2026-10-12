#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
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
source "${SCRIPT_DIR}/lib/diagnose-common.sh"

PROC_CPUINFO="${DIAGNOSE_PROC_CPUINFO:-/proc/cpuinfo}"
PROC_CMDLINE="${DIAGNOSE_PROC_CMDLINE:-/proc/cmdline}"
DMESG_LOG="${DIAGNOSE_DMESG_LOG:-/var/log/dmesg}"
SYSFS_PCI_DEVICES_ROOT="${DIAGNOSE_SYSFS_PCI_DEVICES_ROOT:-/sys/bus/pci/devices}"
PCI_P2PDMA_DEBUGFS="${DIAGNOSE_PCI_P2PDMA_DEBUGFS:-/sys/kernel/debug/pci_p2pdma}"
PREREQS_PASS=1
PREREQS_INCONCLUSIVE=0

TEST_MOCK_ACTIVE=0
for mock_name in \
    TEST_MOCK_HIP_IPC TEST_MOCK_TRANSFERBENCH TEST_MOCK_TRANSFERBENCH_OUT \
    TEST_MOCK_RCCL TEST_MOCK_RCCL_OUT TEST_MOCK_IOMMU TEST_MOCK_GPU_COUNT \
    TEST_MOCK_GPU0_BDF TEST_MOCK_GPU1_BDF TEST_MOCK_KERNEL_ERRORS; do
    if [[ -n "${!mock_name:-}" ]]; then
        TEST_MOCK_ACTIVE=1
        break
    fi
done

if [[ "$TEST_MOCK_ACTIVE" -eq 1 && "${TEST_MODE:-}" != "YES" ]]; then
    echo "ERROR: TEST_MOCK_* inputs require TEST_MODE=YES; refusing ambiguous mock execution." >&2
    exit 2
fi
if [[ "${TEST_MODE:-}" == "YES" && "$TEST_MOCK_ACTIVE" -eq 0 ]]; then
    echo "ERROR: TEST_MODE=YES requires at least one TEST_MOCK_* input." >&2
    exit 2
fi
if [[ "$TEST_MOCK_ACTIVE" -eq 1 ]]; then
    echo "TEST_MODE = YES"
fi

echo "=========================================="
echo "=== AMD GPU P2P Platform Check ==="
echo "=========================================="
echo

# 1. CPU Check
echo "--- 1. CPU & Socket Topology ---"
CPU_MODEL=$(grep -m1 "model name" "$PROC_CPUINFO" 2>/dev/null | cut -d: -f2 | xargs || true)
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
HB_DEV=$(lspci -D -d 8086:6f00 2>/dev/null | head -n1 || true)
if [[ -n "$HB_DEV" ]]; then
    echo "  Device:   8086:6f00 (Intel Broadwell-EP Host Bridge)"
    echo "  Role:     Host Bridge / DMI2 (devfn 00.0)"
    echo "  Status:   PASS"
else
    OTHER_HB=$(lspci -D -d 8086:* 2>/dev/null | grep -i "host bridge" | head -n1 || true)
    echo "  Device:   ${OTHER_HB:-None detected}"
    echo "  Status:   WARN (Target 8086:6f00 not matched; verify if host bridge supports P2PDMA)"
    PREREQS_PASS=0
fi
echo

# 3. PCIe Topology and Endpoints
echo "--- 3. GPUs & Root Ports ---"
GPU_COUNT=0
GPUS=()
if [[ -n "${TEST_MOCK_GPU_COUNT:-}" ]]; then
    GPU_COUNT="$TEST_MOCK_GPU_COUNT"
    echo "  [TEST MOCK] Injected GPU Count: $GPU_COUNT"
    if [[ ! "$GPU_COUNT" =~ ^[0-9]+$ ]]; then
        echo "  Status:   FAIL (invalid mocked GPU count)"
        GPU_COUNT=0
        PREREQS_PASS=0
    fi
    if [[ "$GPU_COUNT" =~ ^[0-9]+$ && $GPU_COUNT -ge 1 ]]; then GPUS+=("${TEST_MOCK_GPU0_BDF:-0000:05:00.0}"); fi
    if [[ "$GPU_COUNT" =~ ^[0-9]+$ && $GPU_COUNT -ge 2 ]]; then GPUS+=("${TEST_MOCK_GPU1_BDF:-0000:08:00.0}"); fi
else
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
        SYS_PATH="${SYSFS_PCI_DEVICES_ROOT}/${BDF}"
        SPEED=$(cat "${SYS_PATH}/current_link_speed" 2>/dev/null || echo "Unknown")
        WIDTH=$(cat "${SYS_PATH}/current_link_width" 2>/dev/null || echo "Unknown")
        echo "  GPU $((GPU_COUNT-1)): $BDF | Link: $SPEED x$WIDTH"
    done < <(lspci -D -d 1002:7551 2>/dev/null || true)
fi

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
HOST_BRIDGES_SAME=0
if [[ $GPU_COUNT -ge 2 ]]; then
    GPU0="${GPUS[0]}"
    GPU1="${GPUS[1]}"
    ROOT_BUS0="$(get_pci_root_bus "$GPU0" || true)"
    ROOT_BUS1="$(get_pci_root_bus "$GPU1" || true)"
    RP0="$(get_upstream_root_port "$GPU0" || true)"
    RP1="$(get_upstream_root_port "$GPU1" || true)"
    HB0=""
    HB1=""
    if [[ -n "$ROOT_BUS0" ]]; then HB0="$(find_6f00_host_bridge_for_root_bus "$ROOT_BUS0" || true)"; fi
    if [[ -n "$ROOT_BUS1" ]]; then HB1="$(find_6f00_host_bridge_for_root_bus "$ROOT_BUS1" || true)"; fi
    echo "  GPU0 Root Bus:           ${ROOT_BUS0:-Unknown}"
    echo "  GPU1 Root Bus:           ${ROOT_BUS1:-Unknown}"
    echo "  GPU0 Upstream Root Port: ${RP0:-Unknown}"
    echo "  GPU1 Upstream Root Port: ${RP1:-Unknown}"
    echo "  GPU0 8086:6f00 Host:     ${HB0:-Unknown}"
    echo "  GPU1 8086:6f00 Host:     ${HB1:-Unknown}"
    if [[ -n "$HB0" && "$HB0" == "$HB1" ]]; then
        HOST_BRIDGES_SAME=1
        echo "  Host Bridge Domain:      SAME (8086:6f00 at $HB0)"
    elif [[ -n "$HB0" && -n "$HB1" ]]; then
        echo "  Host Bridge Domain:      DIFFERENT ($HB0 vs $HB1)"
        PREREQS_PASS=0
    else
        echo "  Host Bridge Domain:      INCONCLUSIVE (root bus or matching 8086:6f00 bridge unavailable)"
        PREREQS_PASS=0
        PREREQS_INCONCLUSIVE=1
    fi
    if [[ -n "$RP0" && -n "$RP1" && "$RP0" != "$RP1" ]]; then
        echo "  Root Port Relationship:  DIFFERENT_ROOT_PORTS"
        ROOT_PORTS_DISTINCT=1
    elif [[ -n "$RP0" && "$RP0" == "$RP1" ]]; then
        echo "  Root Port Relationship:  SAME_ROOT_PORT (cross-root-port target not met)"
        PREREQS_PASS=0
    else
        echo "  Root Port Relationship:  UNKNOWN"
        PREREQS_PASS=0
        PREREQS_INCONCLUSIVE=1
    fi
fi
echo

# 5. DMA Mask and IOMMU
echo "--- 5. DMA Mask & IOMMU ---"
IOMMU_TRANSLATED=0
if [[ -n "${TEST_MOCK_IOMMU:-}" ]]; then
    if [[ "$TEST_MOCK_IOMMU" == "TRANSLATED" ]]; then
        IOMMU_TRANSLATED=1
        echo "  IOMMU:        Intel VT-d Translated (TEST MOCK)"
        echo "  Status:       PASS"
    elif [[ "$TEST_MOCK_IOMMU" == "PASSTHROUGH" ]]; then
        echo "  IOMMU:        Passthrough (TEST MOCK)"
        echo "  Status:       INCONCLUSIVE (passthrough was not the validated configuration; request-address behavior is untraced)"
        PREREQS_PASS=0
        PREREQS_INCONCLUSIVE=1
    else
        echo "  IOMMU:        Unknown / Unconfirmed (TEST MOCK: $TEST_MOCK_IOMMU)"
        echo "  Status:       INCONCLUSIVE (Translated domain not confirmed)"
        PREREQS_PASS=0
        PREREQS_INCONCLUSIVE=1
    fi
else
    if grep -q "iommu=pt" "$PROC_CMDLINE" 2>/dev/null; then
        echo "  IOMMU:        Passthrough (iommu=pt active)"
        echo "  Status:       INCONCLUSIVE (passthrough was not the validated configuration; request-address behavior is untraced)"
        PREREQS_PASS=0
        PREREQS_INCONCLUSIVE=1
    elif grep -q "Default domain type: Translated" "$DMESG_LOG" 2>/dev/null || (command -v journalctl >/dev/null 2>&1 && journalctl -k -b 0 2>/dev/null | grep -q "Default domain type: Translated"); then
        IOMMU_TRANSLATED=1
        echo "  IOMMU:        Intel VT-d Translated (confirmed by kernel log)"
        echo "  Status:       PASS"
    else
        echo "  IOMMU:        Unknown / Unconfirmed (iommu=pt absent, but no positive Translated confirmation in kernel log)"
        echo "  Status:       INCONCLUSIVE (Translated DMA-FQ domain not confirmed)"
        PREREQS_PASS=0
        PREREQS_INCONCLUSIVE=1
    fi
fi

for BDF in "${GPUS[@]}"; do
    MASK=$(cat "${SYSFS_PCI_DEVICES_ROOT}/${BDF}/dma_mask_bits" 2>/dev/null || echo "Unknown")
    echo "  GPU $BDF DMA mask: $MASK-bit"
    if [[ ! "$MASK" =~ ^[0-9]+$ ]]; then
        echo "  Status:       INCONCLUSIVE (DMA mask could not be read)"
        PREREQS_PASS=0
        PREREQS_INCONCLUSIVE=1
    fi
done
echo

# 6. Kernel & P2PDMA Whitelist Check
echo "--- 6. Kernel & P2PDMA Whitelist Detection ---"
KERNEL_VER=$(uname -r)
echo "  Running Kernel: $KERNEL_VER"
WHITELIST_STATUS="UNKNOWN"
if [[ -f "$PCI_P2PDMA_DEBUGFS" ]]; then
    if grep -q "8086:6f00" "$PCI_P2PDMA_DEBUGFS" 2>/dev/null; then
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
KERNEL_LOG_AVAILABLE=0
MOCK_DMAR_ADDITION=0
if [[ -n "${TEST_MOCK_KERNEL_ERRORS:-}" ]]; then
    if [[ "${TEST_MOCK_KERNEL_ERRORS}" =~ ^[0-9]+$ ]]; then
        DMAR_FAULTS="$TEST_MOCK_KERNEL_ERRORS"
        MOCK_DMAR_ADDITION="$TEST_MOCK_KERNEL_ERRORS"
    else
        echo "  Kernel log counters: INCONCLUSIVE (invalid test value)"
        PREREQS_INCONCLUSIVE=1
    fi
fi
if command -v journalctl >/dev/null 2>&1 && KERNEL_LOG=$(journalctl -k -b 0 2>/dev/null) && [[ -n "$KERNEL_LOG" ]]; then
    KERNEL_LOG_AVAILABLE=1
elif [[ -r "$DMESG_LOG" ]] && KERNEL_LOG=$(cat "$DMESG_LOG" 2>/dev/null) && [[ -n "$KERNEL_LOG" ]]; then
    KERNEL_LOG_AVAILABLE=1
fi
if [[ "$KERNEL_LOG_AVAILABLE" -eq 1 ]]; then
    DMAR_FAULTS=$(( DMAR_FAULTS + $(printf '%s\n' "$KERNEL_LOG" | grep -ciE "DMAR:.*fault" || true) ))
    AER_ERRORS=$(printf '%s\n' "$KERNEL_LOG" | grep -ciE "AER:.*error" || true)
    RESETS=$(printf '%s\n' "$KERNEL_LOG" | grep -ciE "amdgpu:.*gpu reset" || true)
fi
echo "  DMAR Faults:  $DMAR_FAULTS"
echo "  AER Errors:   $AER_ERRORS"
echo "  GPU Resets:   $RESETS"
if [[ "$KERNEL_LOG_AVAILABLE" -eq 1 && $DMAR_FAULTS -eq 0 && $AER_ERRORS -eq 0 && $RESETS -eq 0 ]]; then
    echo "  Status:       PASS (Clean kernel log)"
elif [[ "$KERNEL_LOG_AVAILABLE" -eq 1 ]]; then
    echo "  Status:       FAIL (Prior bus errors or resets detected)"
    PREREQS_PASS=0
fi
if [[ "$KERNEL_LOG_AVAILABLE" -eq 0 ]]; then
    echo "  Status:       INCONCLUSIVE (kernel error log is unavailable)"
    PREREQS_PASS=0
    PREREQS_INCONCLUSIVE=1
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
    elif [[ $PREREQS_INCONCLUSIVE -eq 1 ]]; then
        echo "P2P_PREREQUISITES = INCONCLUSIVE"
        echo "DIRECT_P2P_READY = INCONCLUSIVE"
        echo "Reason: One or more required platform facts could not be confirmed."
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
        elif [[ $IPC_RET -eq 3 ]]; then
            HIP_IPC_RESULT="INCONCLUSIVE"
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
    if [[ -n "${TEST_MOCK_TRANSFERBENCH_OUT:-}" ]]; then
        TB_OUT="$TEST_MOCK_TRANSFERBENCH_OUT"
        TB_RET=0
        TB_BIN="mock"
    fi
    if [[ -n "$TB_BIN" ]]; then
        if [[ -z "${TEST_MOCK_TRANSFERBENCH_OUT:-}" ]]; then
            set +e
            TB_OUT=$(NUM_CPU_DEVICES=0 "$TB_BIN" p2p 2>&1)
            TB_RET=$?
            set -e
        fi
        if [[ $TB_RET -ne 0 ]] || echo "$TB_OUT" | grep -qiE "No valid transfers|error|failed"; then
            TB_RESULT="FAIL"
            echo "  TransferBench execution: FAIL"
        else
            TB_PARSE=$(printf '%s\n' "$TB_OUT" | awk -f "${SCRIPT_DIR}/lib/transferbench-parser.awk")
            if [[ "$TB_PARSE" == "PASS" ]]; then
                TB_RESULT="PASS"
                echo "  TransferBench execution: PASS (GPU0->GPU1 and GPU1->GPU0 bandwidth verified)"
            elif [[ "$TB_PARSE" == "INCONCLUSIVE" ]]; then
                TB_RESULT="INCONCLUSIVE"
                echo "  TransferBench execution: INCONCLUSIVE (only self-transfers or host/CPU transfers detected)"
            else
                TB_RESULT="FAIL"
                echo "  TransferBench execution: FAIL (no valid peer transfers detected)"
            fi
        fi
    else
        echo "  [SKIP] TransferBench binary not found at default paths (EXTERNAL_DEPENDENCY)."
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
    if [[ -n "${TEST_MOCK_RCCL_OUT:-}" ]]; then
        RCCL_OUT="$TEST_MOCK_RCCL_OUT"
        RCCL_RET=0
        RCCL_TEST_BIN="mock"
    fi
    if [[ -n "$RCCL_TEST_BIN" ]]; then
        if [[ -z "${TEST_MOCK_RCCL_OUT:-}" ]]; then
            set +e
            export NCCL_P2P_LEVEL=PHB
            export NCCL_DEBUG=INFO
            export NCCL_DEBUG_SUBSYS=INIT,ENV
            RCCL_OUT=$("$RCCL_TEST_BIN" -b 64M -e 64M -g 2 2>&1)
            RCCL_RET=$?
            set -e
        fi
        RCCL_RESULT="$(classify_rccl_output "$RCCL_OUT" "$RCCL_RET")"
        if [[ "$RCCL_RESULT" == "FAIL" ]]; then
            echo "  RCCL P2P AllReduce: FAIL (SHM fallback or execution error)"
        elif [[ "$RCCL_RESULT" == "PASS" ]]; then
            echo "  RCCL P2P AllReduce: PASS (P2P transport confirmed)"
        else
            echo "  RCCL P2P AllReduce: INCONCLUSIVE (requires isAllDirectP2p=1 and a via P2P/IPC transport line)"
        fi
    else
        echo "  [SKIP] rccl-tests binary not found at default paths (EXTERNAL_DEPENDENCY)."
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
HEALTH_INCONCLUSIVE=0
if [[ "$KERNEL_LOG_AVAILABLE" -eq 1 ]] && command -v journalctl >/dev/null 2>&1 && POST_KERNEL_LOG=$(journalctl -k -b 0 2>/dev/null) && [[ -n "$POST_KERNEL_LOG" ]]; then
    POST_DMAR=$(( $(printf '%s\n' "$POST_KERNEL_LOG" | grep -ciE "DMAR:.*fault" || true) + MOCK_DMAR_ADDITION ))
    POST_AER=$(printf '%s\n' "$POST_KERNEL_LOG" | grep -ciE "AER:.*error" || true)
    POST_RESETS=$(printf '%s\n' "$POST_KERNEL_LOG" | grep -ciE "amdgpu:.*gpu reset" || true)
elif [[ "$KERNEL_LOG_AVAILABLE" -eq 1 && -r "$DMESG_LOG" ]] && POST_KERNEL_LOG=$(cat "$DMESG_LOG" 2>/dev/null) && [[ -n "$POST_KERNEL_LOG" ]]; then
    POST_DMAR=$(( $(printf '%s\n' "$POST_KERNEL_LOG" | grep -ciE "DMAR:.*fault" || true) + MOCK_DMAR_ADDITION ))
    POST_AER=$(printf '%s\n' "$POST_KERNEL_LOG" | grep -ciE "AER:.*error" || true)
    POST_RESETS=$(printf '%s\n' "$POST_KERNEL_LOG" | grep -ciE "amdgpu:.*gpu reset" || true)
else
    HEALTH_INCONCLUSIVE=1
    PREREQS_INCONCLUSIVE=1
fi
if [[ "$POST_DMAR" -lt "$DMAR_FAULTS" || "$POST_AER" -lt "$AER_ERRORS" || "$POST_RESETS" -lt "$RESETS" ]]; then
    HEALTH_INCONCLUSIVE=1
    echo "  Health counters decreased between samples; delta cannot be trusted."
    NEW_DMAR=0
    NEW_AER=0
    NEW_RESETS=0
else
    NEW_DMAR=$((POST_DMAR - DMAR_FAULTS))
    NEW_AER=$((POST_AER - AER_ERRORS))
    NEW_RESETS=$((POST_RESETS - RESETS))
fi
echo "  New DMAR Faults: $NEW_DMAR"
echo "  New AER Errors:  $NEW_AER"
echo "  New GPU Resets:  $NEW_RESETS"
echo

echo "=========================================="
echo "=== Final Full Mode Verdict ==="
echo "=========================================="
if [[ ( $PREREQS_PASS -eq 0 && $PREREQS_INCONCLUSIVE -eq 0 ) || "$HIP_IPC_RESULT" == "FAIL" || "$TB_RESULT" == "FAIL" || "$RCCL_RESULT" == "FAIL" || $NEW_DMAR -gt 0 || $NEW_AER -gt 0 || $NEW_RESETS -gt 0 ]]; then
    echo "P2P_PREREQUISITES = $([[ $PREREQS_PASS -eq 1 ]] && echo PASS || { [[ $PREREQS_INCONCLUSIVE -eq 1 ]] && echo INCONCLUSIVE || echo FAIL; })"
    echo "DIRECT_P2P_READY = NO"
elif [[ $PREREQS_INCONCLUSIVE -eq 1 || "$HEALTH_INCONCLUSIVE" -eq 1 || "$HIP_IPC_RESULT" == "SKIP" || "$HIP_IPC_RESULT" == "INCONCLUSIVE" || "$TB_RESULT" == "SKIP" || "$RCCL_RESULT" == "SKIP" || "$TB_RESULT" == "INCONCLUSIVE" || "$RCCL_RESULT" == "INCONCLUSIVE" ]]; then
    echo "P2P_PREREQUISITES = $([[ $PREREQS_PASS -eq 1 ]] && echo PASS || echo INCONCLUSIVE)"
    echo "DIRECT_P2P_READY = INCONCLUSIVE"
    echo "Reason: One or more active benchmark tools were skipped or inconclusive."
elif [[ "$HIP_IPC_RESULT" == "PASS" && "$TB_RESULT" == "PASS" && "$RCCL_RESULT" == "PASS" && $NEW_DMAR -eq 0 && $NEW_AER -eq 0 && $NEW_RESETS -eq 0 ]]; then
    echo "P2P_PREREQUISITES = PASS"
    if [[ $TEST_MOCK_ACTIVE -eq 1 ]]; then
        echo "DIRECT_P2P_READY = TEST_ONLY"
        echo "Notice: Verified via injected test mocks only. Real hardware execution required for production confirmation."
    else
        echo "DIRECT_P2P_READY = YES"
        echo "All peer verification tests passed cleanly with 0 kernel errors."
    fi
else
    echo "DIRECT_P2P_READY = INCONCLUSIVE"
fi
echo "=========================================="
