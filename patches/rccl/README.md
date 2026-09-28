# RCCL Host Bridge P2P Override Patch

## Overview
This patch allows ROCm RCCL to utilize direct peer-to-peer (P2P) transfers across PCIe Root Ports under the same Host Bridge / Processor Host Bridge (PHB).

## Metadata
* **Base Repository**: `https://github.com/ROCm/rccl`
* **Base Tag**: `rocm-7.2.0` (RCCL `2.27.7`)
* **Base Git SHA**: `0d2c4fd4c5ea8aa96b4ac4eb468fb4146ab2c921`
* **Target File**: `src/graph/paths.cc`
* **Patch File**: `0001-graph-honor-explicit-p2p-level-after-platform-limit.patch`

## Distinguishing Patch Mechanism vs Runtime Setting
It is critical to distinguish between:
1. **Patch Mechanism**:
   - The code fix relocates `ncclGetUserP2pLevel(&p2pLevel)` to execute after the built-in default demotion (`if (p2pLevel == PATH_SYS) p2pLevel = PATH_PXB;`).
   - This ensures that if the user explicitly specifies an environment override, RCCL respects that override rather than clamping it back down.
2. **Validated Runtime Setting**:
   - At runtime, the user provides the environment override:
     ```bash
     export NCCL_P2P_LEVEL=PHB
     ```
   - On the Broadwell-EP reference testbed, `NCCL_P2P_LEVEL=PHB` enables RCCL to route AllReduce and SendRecv collectives directly over PCIe P2P/IPC (`isAllDirectP2p = 1`, `Channel 00 : ... via P2P/IPC`), completely eliminating SHM fallback and delivering ~9.49 GB/s large-message bus bandwidth.
