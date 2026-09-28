#!/usr/bin/env bash
#
# check-hip-ipc.sh - Safe wrapper to verify cross-process HIP IPC memory handle sharing
#
# Provenance & Reproduction Notes:
#   This script executes an external standalone HIP IPC test binary.
#   Origin: ROCm HIP test suite / HIP sample (e.g. hipIpcMemAccess or hip_ipc_standalone.cpp).
#
# Build Instructions:
#   hipcc -O3 -std=c++17 hip_ipc_standalone.cpp -o bin/hip_ipc_standalone
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
if "$IPC_BIN"; then
    echo "[PASS] HIP IPC Verification Complete (0 errors)."
    exit 0
else
    echo "[FAIL] HIP IPC Verification encountered errors."
    exit 1
fi
