#!/usr/bin/env bash
#
# run-rccl.sh - Safe wrapper to execute RCCL AllReduce benchmark with PHB override
#
set -euo pipefail

echo "=== RCCL AllReduce P2P Verification ==="
export NCCL_P2P_LEVEL=PHB
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,COLL,ENV

AR_BIN="${1:-}"
if [[ -z "$AR_BIN" ]]; then
    for candidate in /opt/rocm/bin/all_reduce_perf ./bin/all_reduce_perf; do
        if [[ -x "$candidate" ]]; then
            AR_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$AR_BIN" || ! -x "$AR_BIN" ]]; then
    echo "Notice: all_reduce_perf binary not found."
    echo "Please build rccl-tests from: https://github.com/ROCm/rccl-tests"
    exit 0
fi

echo "Running all_reduce_perf with NCCL_P2P_LEVEL=PHB..."
"$AR_BIN" -b 1M -e 128M -f 2 -g 2
