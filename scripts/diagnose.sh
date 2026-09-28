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

TEST_MOCK_ACTIVE=0
if [[ -n "${TEST_MOCK_HIP_IPC:-}" || -n "${TEST_MOCK_TRANSFERBENCH:-}" || -n "${TEST_MOCK_TRANSFERBENCH_OUT:-}" || -n "${TEST_MOCK_RCCL:-}" || -n "${TEST_MOCK_RCCL_OUT:-}" || -n "${TEST_MOCK_IOMMU:-}" || -n "${TEST_MOCK_GPU_COUNT:-}" || -n "${TEST_MOCK_KERNEL_ERRORS:-}" ]]; then
    TEST_MOCK_ACTIVE=1
fi

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
if [[ -n "${TEST_MOCK_GPU_COUNT:-}" ]]; then
    GPU_COUNT="$TEST_MOCK_GPU_COUNT"
    echo "  [TEST MOCK] Injected GPU Count: $GPU_COUNT"
    if [[ $GPU_COUNT -ge 1 ]]; then GPUS+=("0000:05:00.0"); fi
    if [[ $GPU_COUNT -ge 2 ]]; then GPUS+=("0000:08:00.0"); fi
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
        SYS_PATH="/sys/bus/pci/devices/${BDF}"
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
if [[ -n "${TEST_MOCK_IOMMU:-}" ]]; then
    if [[ "$TEST_MOCK_IOMMU" == "TRANSLATED" ]]; then
        IOMMU_TRANSLATED=1
        echo "  IOMMU:        Intel VT-d Translated (TEST MOCK)"
        echo "  Status:       PASS"
    elif [[ "$TEST_MOCK_IOMMU" == "PASSTHROUGH" ]]; then
        echo "  IOMMU:        Passthrough (TEST MOCK)"
        echo "  Status:       WARN (Passthrough mode may expose physical addresses >44-bit)"
        PREREQS_PASS=0
    else
        echo "  IOMMU:        Unknown / Unconfirmed (TEST MOCK: $TEST_MOCK_IOMMU)"
        echo "  Status:       WARN (Cannot confirm Translated domain; fail-closed)"
        PREREQS_PASS=0
    fi
else
    if grep -q "Default domain type: Translated" /var/log/dmesg 2>/dev/null || (command -v journalctl >/dev/null 2>&1 && journalctl -k -b 0 2>/dev/null | grep -q "Default domain type: Translated"); then
        IOMMU_TRANSLATED=1
        echo "  IOMMU:        Intel VT-d Translated (confirmed by kernel log)"
        echo "  Status:       PASS"
    elif grep -q "iommu=pt" /proc/cmdline 2>/dev/null; then
        echo "  IOMMU:        Passthrough (iommu=pt active)"
        echo "  Status:       WARN (Passthrough mode may expose physical addresses >44-bit)"
        PREREQS_PASS=0
    else
        echo "  IOMMU:        Unknown / Unconfirmed (iommu=pt absent, but no positive Translated confirmation in kernel log)"
        echo "  Status:       WARN (Cannot confirm Translated DMA-FQ domain; fail-closed)"
        PREREQS_PASS=0
    fi
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
if [[ -n "${TEST_MOCK_KERNEL_ERRORS:-}" ]]; then
    DMAR_FAULTS="$TEST_MOCK_KERNEL_ERRORS"
fi
if command -v journalctl >/dev/null 2>&1; then
    DMAR_FAULTS=$(( DMAR_FAULTS + $(journalctl -k -b 0 2>/dev/null | grep -ciE "DMAR:.*fault" || true) ))
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

parse_transferbench_matrix() {
    awk '
function parse_cell(val) {
    gsub(/[ \t\r\n]/, "", val);
    if (val ~ /^[0-9]+(\.[0-9]+)?$/ && (val + 0) > 0) return 1;
    return 0;
}
BEGIN {
    peer = 0; self = 0; cpu = 0; num_dst = 0; in_mat = 0;
    list_s = -1; list_d = -1; in_list = 0;
}
# Format 1: Matrix Header (e.g. "SRC+EXE\DST    GPU 00    GPU 01")
/SRC.*DST/ {
    in_mat = 1; num_dst = 0;
    line = $0;
    p = 1;
    while (match(substr(line, p), /(GPU|CPU)[ \t]*([0-9]+)/)) {
        match_str = substr(line, p + RSTART - 1, RLENGTH);
        num_dst++;
        if (match_str ~ /^GPU/) dst_type[num_dst] = "GPU";
        else dst_type[num_dst] = "CPU";
        sub(/^(GPU|CPU)[ \t]*/, "", match_str);
        dst_id[num_dst] = match_str + 0;
        p += RSTART + RLENGTH - 1;
    }
    next;
}
# Format 1: Matrix Row (e.g. "GPU 00 -> N/A 10.29")
in_mat && /^[ \t]*(GPU|CPU)[ \t]*[0-9]+[ \t]*->/ {
    line = $0;
    arrow_pos = index(line, "->");
    prefix = substr(line, 1, arrow_pos - 1);
    data = substr(line, arrow_pos + 2);

    src_type = (prefix ~ /GPU/) ? "GPU" : "CPU";
    sub(/^[ \t]*(GPU|CPU)[ \t]*/, "", prefix);
    src_id = prefix + 0;

    n = split(data, cells);
    for (i = 1; i <= n && i <= num_dst; i++) {
        if (parse_cell(cells[i])) {
            if (src_type == "GPU" && dst_type[i] == "GPU") {
                if (src_id != dst_id[i]) peer++;
                else self++;
            } else {
                cpu++;
            }
        }
    }
    next;
}
# Format 2: CSV format (e.g. "GPU0,GPU1,GPU0,67108864,0.0065,10.29")
/^[ \t]*(GPU|CPU)[0-9]+,[ \t]*(GPU|CPU)[0-9]+/ {
    n_f = split($0, f, ",");
    s_type = (f[1] ~ /GPU/) ? "GPU" : "CPU";
    d_type = (f[2] ~ /GPU/) ? "GPU" : "CPU";
    sub(/^[ \t]*(GPU|CPU)/, "", f[1]); s_id = f[1] + 0;
    sub(/^[ \t]*(GPU|CPU)/, "", f[2]); d_id = f[2] + 0;
    for (i = 3; i <= n_f; i++) {
        if (parse_cell(f[i])) {
            if (s_type == "GPU" && d_type == "GPU") {
                if (s_id != d_id) peer++;
                else self++;
            } else {
                cpu++;
            }
        }
    }
    next;
}
# Format 3: List style header
/(dma|push|pull)_[0-9]+_to_[0-9]+/ || /Direction:[ \t]*GPU[ \t]*[0-9]+[ \t]*->[ \t]*GPU[ \t]*[0-9]+/ {
    in_list = 1;
    if (match($0, /GPU[ \t]*([0-9]+)[ \t]*->[ \t]*GPU[ \t]*([0-9]+)/)) {
        str = substr($0, RSTART, RLENGTH);
        sub(/GPU[ \t]*/, "", str);
        list_s = substr(str, 1, index(str, "->") - 1) + 0;
        sub(/.*->[ \t]*GPU[ \t]*/, "", str);
        list_d = str + 0;
    } else if (match($0, /(dma|push|pull)_([0-9]+)_to_([0-9]+)/)) {
        str = substr($0, RSTART, RLENGTH);
        sub(/^(dma|push|pull)_/, "", str);
        list_s = substr(str, 1, index(str, "_to_") - 1) + 0;
        sub(/.*_to_/, "", str);
        list_d = str + 0;
    }
}
# Format 3: List style bandwidth line
in_list && /([0-9]+\.[0-9]+)[ \t]*GB\/s/ {
    if (match($0, /([0-9]+\.[0-9]+)[ \t]*GB\/s/)) {
        bw = substr($0, RSTART, RLENGTH);
        sub(/[ \t]*GB\/s/, "", bw);
        if ((bw + 0) > 0) {
            if (list_s >= 0 && list_d >= 0) {
                if (list_s != list_d) peer++;
                else self++;
            }
        }
    }
}
END {
    if (peer > 0) print "PASS";
    else if (self > 0 || cpu > 0) print "INCONCLUSIVE";
    else print "FAIL";
}
'
}

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
            TB_PARSE=$(echo "$TB_OUT" | parse_transferbench_matrix)
            if [[ "$TB_PARSE" == "PASS" ]]; then
                TB_RESULT="PASS"
                echo "  TransferBench execution: PASS (Peer GPU transfers measured)"
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
        if [[ $RCCL_RET -ne 0 ]] || echo "$RCCL_OUT" | grep -qiE "(via SHM|isAllDirectP2p 0|P2P direct disabled|P2P disabled)"; then
            RCCL_RESULT="FAIL"
            echo "  RCCL P2P AllReduce: FAIL (SHM fallback or execution error)"
        elif echo "$RCCL_OUT" | grep -qiE "via P2P/(IPC|direct pointer|CUMEM|direct)|via P2P"; then
            RCCL_RESULT="PASS"
            echo "  RCCL P2P AllReduce: PASS (P2P transport confirmed)"
        else
            RCCL_RESULT="INCONCLUSIVE"
            echo "  RCCL P2P AllReduce: INCONCLUSIVE (exit 0, but no explicit P2P transport logs observed)"
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
elif [[ "$HIP_IPC_RESULT" == "SKIP" || "$TB_RESULT" == "SKIP" || "$RCCL_RESULT" == "SKIP" || "$TB_RESULT" == "INCONCLUSIVE" || "$RCCL_RESULT" == "INCONCLUSIVE" ]]; then
    echo "P2P_PREREQUISITES = PASS"
    echo "DIRECT_P2P_READY = INCONCLUSIVE"
    echo "Reason: One or more active benchmark tools were skipped or inconclusive."
elif [[ "$HIP_IPC_RESULT" == "PASS" && "$TB_RESULT" == "PASS" && "$RCCL_RESULT" == "PASS" && $NEW_DMAR -eq 0 && $NEW_AER -eq 0 && $NEW_RESETS -eq 0 ]]; then
    echo "P2P_PREREQUISITES = PASS"
    if [[ $TEST_MOCK_ACTIVE -eq 1 ]]; then
        echo "DIRECT_P2P_READY = TEST_ONLY"
        echo "TEST_MODE = YES"
        echo "Notice: Verified via injected test mocks only. Real hardware execution required for production confirmation."
    else
        echo "DIRECT_P2P_READY = YES"
        echo "All peer verification tests passed cleanly with 0 kernel errors."
    fi
else
    echo "DIRECT_P2P_READY = INCONCLUSIVE"
fi
echo "=========================================="
