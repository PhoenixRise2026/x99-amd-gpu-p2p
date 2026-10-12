#!/usr/bin/env bash
#
# check-hip-ipc.sh - Safe wrapper to verify cross-process HIP IPC memory handle sharing
#
# Provenance & Execution Notes:
#   This script executes an external standalone HIP IPC test binary (EXTERNAL_DEPENDENCY).
#   The validation test binary is an external dependency. A zero exit status alone is not a pass:
#   output must show verified reads and writes for both GPU 0 -> GPU 1 and GPU 1 -> GPU 0.
#
# Validated Environment Setting:
#   export HSA_ENABLE_IPC_MODE_LEGACY=0
#   (Note: This was the verified configuration on the reference single-socket Broadwell system;
#    do not generalize as mandatory for all ROCm deployments without verification.)
#
set -euo pipefail

echo "=== HIP IPC Memory Sharing Verification ==="

# Set verified runtime environment variable
export HSA_ENABLE_IPC_MODE_LEGACY=0

IPC_BIN=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --binary)
            IPC_BIN="${2:-}"
            shift 2 || true
            ;;
        *)
            if [[ -z "$IPC_BIN" ]]; then
                IPC_BIN="$1"
            fi
            shift || true
            ;;
    esac
done

if [[ -z "$IPC_BIN" ]]; then
    for candidate in ./bin/hip_ipc_standalone /opt/rocm/bin/hip_ipc_standalone ./hip_ipc_standalone; do
        if [[ -x "$candidate" ]]; then
            IPC_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$IPC_BIN" || ! -x "$IPC_BIN" ]]; then
    echo "[SKIP] HIP IPC test binary not found (EXTERNAL_DEPENDENCY)."
    echo "Notice: An external compiled HIP IPC test binary is required (e.g. from ROCm HIP test suite or samples)."
    echo "Specify the path using: ./scripts/check-hip-ipc.sh --binary <path-to-binary>"
    exit 2
fi

echo "Running HIP IPC validation using: $IPC_BIN"
set +e
IPC_OUT=$("$IPC_BIN" 2>&1)
IPC_RET=$?
set -e
printf '%s\n' "$IPC_OUT"

if [[ $IPC_RET -ne 0 ]]; then
    echo "[FAIL] HIP IPC Verification encountered errors."
    exit 1
fi

IPC_EVIDENCE=$(printf '%s\n' "$IPC_OUT" | awk -f "$(dirname "${BASH_SOURCE[0]}")/lib/hip-ipc-parser.awk")
if [[ "$IPC_EVIDENCE" == "PASS" ]]; then
    echo "[PASS] HIP IPC showed verified forward reads and reverse writes in both GPU directions."
    exit 0
fi
if [[ "$IPC_EVIDENCE" == "FAIL" ]]; then
    echo "[FAIL] At least one reported HIP IPC integrity case failed."
    exit 1
fi

echo "[INCONCLUSIVE] Binary exited 0 but did not print complete bidirectional integrity evidence."
exit 3
