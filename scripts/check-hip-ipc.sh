#!/usr/bin/env bash
#
# check-hip-ipc.sh - Safe wrapper to verify cross-process HIP IPC memory handle sharing
#
set -euo pipefail

echo "=== HIP IPC Memory Sharing Verification ==="
IPC_BIN="${1:-}"

if [[ -z "$IPC_BIN" ]]; then
    for candidate in ./bin/hip_ipc_standalone /opt/rocm/bin/hip_ipc_standalone; do
        if [[ -x "$candidate" ]]; then
            IPC_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$IPC_BIN" || ! -x "$IPC_BIN" ]]; then
    echo "Notice: hip_ipc_standalone test binary not found."
    echo "To build, compile an exec-based HIP IPC exporter/importer using hipcc:"
    echo "  hipcc -O2 hip_ipc_standalone.cpp -o bin/hip_ipc_standalone"
    exit 0
fi

echo "Running HIP IPC validation using: $IPC_BIN"
"$IPC_BIN"
echo "HIP IPC Verification Complete."
