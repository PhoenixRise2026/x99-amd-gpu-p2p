#!/usr/bin/env bash
#
# run-transferbench.sh - Safe wrapper to execute TransferBench P2P matrix benchmark
#
set -euo pipefail

TB_BIN="${1:-}"
if [[ -z "$TB_BIN" ]]; then
    for candidate in /opt/rocm/bin/TransferBench ./bin/TransferBench; do
        if [[ -x "$candidate" ]]; then
            TB_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$TB_BIN" || ! -x "$TB_BIN" ]]; then
    echo "Notice: TransferBench binary not found at default paths."
    echo "Please install TransferBench from: https://github.com/ROCm/TransferBench"
    exit 0
fi

echo "=== Running TransferBench P2P Matrix Benchmark ==="
export NUM_CPU_DEVICES=0
echo "Executing: NUM_CPU_DEVICES=0 $TB_BIN p2p"
"$TB_BIN" p2p
