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
   - In stock RCCL (`src/graph/paths.cc`), `ncclGetUserP2pLevel(&p2pLevel)` was called before the Intel x86 platform constraint check:
     ```cpp
     if (arch == NCCL_TOPO_CPU_ARCH_X86 && vendor == NCCL_TOPO_CPU_VENDOR_INTEL) {
       p2pLevel = PATH_PXB;
     }
     ```
   - This hardcoded platform clamp unconditionally demoted `p2pLevel` to `PATH_PXB`, overwriting any prior user override such as `NCCL_P2P_LEVEL=PHB`.
   - The patch relocates `ncclGetUserP2pLevel(&p2pLevel)` to execute *after* the Intel x86 platform clamp, ensuring explicit user override requests take precedence.
2. **Validated Runtime Setting**:
   - At runtime, the user provides the environment override:
     ```bash
     export NCCL_P2P_LEVEL=PHB
     ```
   - On the Broadwell-EP reference testbed, `NCCL_P2P_LEVEL=PHB` allows RCCL to evaluate `path->type <= p2pLevel` (`PATH_PHB <= PATH_PHB`) as true (`*p2p = 1`).
   - Consequently, RCCL's transport selection engine selects `via P2P/IPC` instead of falling back to SHM (`via SHM/direct/direct`), delivering ~9.49 GB/s large-message AllReduce bus bandwidth.

## Topology Level vs Transport Distinction
- `PATH_PXB`, `PATH_PHB`, and `PATH_SYS` are **topology path distance classifications** used to evaluate P2P eligibility.
- `P2P/IPC`, `SHM`, and `NET` are **transport implementations**.
- `PATH_SYS` is not synonymous with SHM; rather, when P2P eligibility fails, RCCL falls back to the SHM transport mechanism.

## Upstream Licensing & Attribution
Upstream RCCL is copyright (c) Advanced Micro Devices, Inc., and includes collective algorithms and infrastructure derived from NVIDIA NCCL (copyright (c) NVIDIA Corporation). This patch is a minimal derived diff against `src/graph/paths.cc` and is governed by the upstream BSD-3-Clause license.
