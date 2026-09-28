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

IPC_BIN="${1:-}"

if [[ -z "$IPC_BIN" ]]; then
    for candidate in ./bin/hip_ipc_standalone /opt/rocm/bin/hip_ipc_standalone ./hip_ipc_standalone; do
        if [[ -x "$candidate" ]]; then
            IPC_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$IPC_BIN" || ! -x "$IPC_BIN" ]]; then
    echo "[SKIP] hip_ipc_standalone test binary not found."
    echo "To build, compile an exec-based HIP IPC test using hipcc:"
    echo "  hipcc -O3 -std=c++17 hip_ipc_standalone.cpp -o bin/hip_ipc_standalone"
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
