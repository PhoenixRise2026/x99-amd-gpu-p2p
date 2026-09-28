#!/usr/bin/env bash
#
# run-rccl.sh - Safe wrapper to execute RCCL AllReduce benchmark with PHB override
#
set -euo pipefail

FULL_MODE=0
AR_BIN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)
            FULL_MODE=1
            shift
            ;;
        --binary)
            AR_BIN="${2:-}"
            shift 2 || true
            ;;
        *)
            if [[ -z "$AR_BIN" ]]; then
                AR_BIN="$1"
            fi
            shift || true
            ;;
    esac
done

echo "=== RCCL AllReduce P2P Verification ==="
export NCCL_P2P_LEVEL=PHB
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,COLL,ENV

if [[ -z "$AR_BIN" ]]; then
    for candidate in /opt/rocm/bin/all_reduce_perf ./bin/all_reduce_perf; do
        if [[ -x "$candidate" ]]; then
            AR_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$AR_BIN" || ! -x "$AR_BIN" ]]; then
    echo "[SKIP] all_reduce_perf binary not found (EXTERNAL_DEPENDENCY)."
    echo "Please build rccl-tests from: https://github.com/ROCm/rccl-tests"
    echo "Usage: ./scripts/run-rccl.sh [--full] [--binary <path-to-all_reduce_perf>]"
    exit 2
fi

# Resolve loaded RCCL library path
RCCL_LIB_RESOLVED="UNKNOWN"
if command -v ldd >/dev/null 2>&1; then
    RCCL_LIB_CANDIDATE=$(ldd "$AR_BIN" 2>/dev/null | grep -i "librccl\.so" | awk '{print $3}' || true)
    if [[ -n "$RCCL_LIB_CANDIDATE" && -f "$RCCL_LIB_CANDIDATE" ]]; then
        RCCL_LIB_RESOLVED=$(realpath "$RCCL_LIB_CANDIDATE" 2>/dev/null || echo "$RCCL_LIB_CANDIDATE")
    fi
fi
echo "RCCL_LIBRARY_REALPATH: ${RCCL_LIB_RESOLVED}"

if [[ $FULL_MODE -eq 1 ]]; then
    echo "Running Full RCCL Performance Sweep (1M to 1024M, Rank=2)..."
    "$AR_BIN" -b 1M -e 1024M -f 2 -g 2
else
    echo "Running Quick Smoke Test (64M, Rank=2)..."
    echo "(Use --full for full 1M-1024M characterization sweep)"
    "$AR_BIN" -b 64M -e 64M -g 2
fi
