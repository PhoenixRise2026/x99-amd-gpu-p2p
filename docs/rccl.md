# RCCL P2P Topology & Optimization on Intel Broadwell

## Overview

RCCL (ROCm Communication Collectives Library) is AMD's collective communication library (derived from NVIDIA NCCL). In distributed tensor parallel inference (such as SGLang TP2), AllReduce operations occur at every transformer layer, making inter-GPU bandwidth and latency a critical bottleneck.

When two GPUs are attached to different Root Ports under the same host bridge, RCCL evaluates their physical topology distance and determines whether direct P2P transport is eligible, or whether communication must fall back to host shared memory (SHM).

---

## Topology Distance Levels vs Transport Selection

It is essential to distinguish between **topology distance classification** and **transport selection**:

### 1. Topology Distance Levels
RCCL classifies the physical interconnect distance between pairs of GPUs using hierarchical path levels:

| Level | Identifier | Internal Enum Value | Description |
| :--- | :--- | :---: | :--- |
| **LOC** | `PATH_LOC` | 0 | Same GPU / loopback |
| **NVL** | `PATH_NVL` | 1 | Dedicated high-speed fabric (xGMI / NVLink) |
| **PIX** | `PATH_PIX` | 3 | Traversal through a single PCIe Switch |
| **PXB** | `PATH_PXB` | 5 | Traversal through multiple PCIe Switches |
| **PHB** | `PATH_PHB` | 8 | Traversal through PCIe Host Bridge / Root Complex |
| **SYS** | `PATH_SYS` | 9 | Traversal at system / inter-socket / fallback distance |

On a single-socket Intel X99 / Broadwell-EP system, GPU 0 (`05:00.0`) and GPU 1 (`08:00.0`) reside under separate Root Ports (`00:02.0` and `00:03.0`) of the same Host Bridge (`00:00.0` `8086:6f00`). Therefore, the physical path distance is **`PATH_PHB`** (enum value 8).

### 2. Transport Mechanisms
- **P2P/IPC**: Direct peer-to-peer DMA over the PCIe bus without copying through host RAM.
- **SHM**: Host shared memory bounce buffers coordinated by the CPU.
- **NET**: Network transport (e.g. RoCE, InfiniBand, or sockets).

`PATH_SYS` (enum value 9) is a topology distance classification, not a transport mechanism. When direct P2P eligibility is rejected (`*p2p = 0`), RCCL's transport selection engine falls back to `via SHM/direct/direct`.

---

## The Role of `NCCL_P2P_LEVEL`

The environment variable `NCCL_P2P_LEVEL` sets the maximum allowable path distance for P2P eligibility:
```bash
export NCCL_P2P_LEVEL=PHB
```
This instructs RCCL that transfers crossing the PCIe Host Bridge (`PATH_PHB`, value 8) should be considered eligible for direct P2P transport.

---

## RCCL Graph Patch: Honor Explicit `NCCL_P2P_LEVEL`

### The Issue in Stock RCCL 7.2.0

In upstream RCCL (`src/graph/paths.cc`), `ncclGetUserP2pLevel(&p2pLevel)` was called before evaluating Intel x86 architecture constraints:
```cpp
  int p2pLevel = PATH_SYS;

  // Stock RCCL queried user override first:
  NCCLCHECK(ncclGetUserP2pLevel(&p2pLevel));

  // Then Intel x86 platform logic executed:
  int arch, vendor, model;
  NCCLCHECK(ncclTopoCpuType(system, &arch, &vendor, &model));
  if (arch == NCCL_TOPO_CPU_ARCH_ARM) p2pLevel = PATH_PXB;
  if (arch == NCCL_TOPO_CPU_ARCH_X86 && vendor == NCCL_TOPO_CPU_VENDOR_INTEL) {
    p2pLevel = PATH_PXB;
  }
```
Because the Intel x86 clamp unconditionally demoted `p2pLevel` to `PATH_PXB` (enum value 5), an explicit user configuration such as `NCCL_P2P_LEVEL=PHB` (enum value 8) was overwritten back to `PATH_PXB` (value 5).

For the physical GPU pair across Root Ports (`path->type = PATH_PHB`, value 8), `path->type <= p2pLevel` (`8 <= 5`) evaluated to false (`*p2p = 0`). Consequently, direct P2P was disabled, and transport selection fell back to SHM staging.

### The Fix

The patch in `patches/rccl/0001-graph-honor-explicit-p2p-level-after-platform-limit.patch` relocates `ncclGetUserP2pLevel(&p2pLevel)` to execute *after* the Intel x86 platform clamp:

```diff
--- a/src/graph/paths.cc
+++ b/src/graph/paths.cc
@@ -322,9 +322,6 @@ ncclResult_t ncclTopoCheckP2p(struct ncclComm* comm, struct ncclTopoSystem* syst
   // In general, use P2P whenever we can.
   int p2pLevel = PATH_SYS;

-  // User override
-  NCCLCHECK(ncclGetUserP2pLevel(&p2pLevel));
-
   // Don't use P2P through ARM CPUs
   int arch, vendor, model;
   NCCLCHECK(ncclTopoCpuType(system, &arch, &vendor, &model));
@@ -336,6 +333,9 @@ ncclResult_t ncclTopoCheckP2p(struct ncclComm* comm, struct ncclTopoSystem* syst
     p2pLevel = PATH_PXB;
   }

+  // User override
+  NCCLCHECK(ncclGetUserP2pLevel(&p2pLevel));
+
   // Compute the PCI distance and compare with the p2pLevel.
   if (path->type <= p2pLevel) *p2p = 1;
```

With this patch, `NCCL_P2P_LEVEL=PHB` successfully restores `p2pLevel = PATH_PHB`. Because `PATH_PHB <= PATH_PHB` is true, direct P2P eligibility is granted, and RCCL selects the high-performance `P2P/IPC` transport.

---

## Benchmarking Collectives: `rccl-tests`

Collective AllReduce performance was evaluated on the reference dual AMD R9700 system using the patched RCCL runtime:

```bash
# Execute benchmark via the automated script:
./scripts/run-rccl.sh
```

### Verified Empirical Performance (Raw Evidence: `rccl.txt`)

All data below is locked to `examples/broadwell-r9700/rccl.txt` (Rank=2 Ring AllReduce):

| Message Size | Transferred Bytes | Hardware Latency (Median) | Bus Bandwidth | Verify Status | Kernel Errors |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **1 MiB** | 1,048,576 | 0.237 ms | 4.418 GB/s | **PASS** | 0 DMAR / 0 AER |
| **4 MiB** | 4,194,304 | 0.603 ms | 6.956 GB/s | **PASS** | 0 DMAR / 0 AER |
| **16 MiB** | 16,777,216 | 1.900 ms | 8.832 GB/s | **PASS** | 0 DMAR / 0 AER |
| **64 MiB** | 67,108,864 | 7.171 ms | 9.359 GB/s | **PASS** | 0 DMAR / 0 AER |
| **256 MiB** | 268,435,456 | 28.286 ms | 9.490 GB/s | **PASS** | 0 DMAR / 0 AER |
| **512 MiB** | 536,870,912 | 56.546 ms | 9.494 GB/s | **PASS** | 0 DMAR / 0 AER |
| **1024 MiB** | 1,073,741,824 | 113.194 ms | 9.486 GB/s | **PASS** | 0 DMAR / 0 AER |

*Note: In 2-rank ring AllReduce, algorithmic bandwidth equals bus bandwidth ($B_{\text{bus}} = B_{\text{alg}}$).*

### Transport Comparison
- **Stock RCCL Behavior**: Direct P2P eligibility rejected (`isAllDirectP2p = 0`); transport fell back to host memory bounce buffers (`via SHM/direct/direct`).
- **Direct P2P Behavior**: Direct P2P eligibility confirmed (`isAllDirectP2p = 1`); transport routed over PCIe P2P DMA (`via P2P/IPC`), achieving a stable ~9.49 GB/s large-message plateau with zero host RAM copies.

---

## Recommended Production Configuration

To run distributed workloads (e.g. SGLang TP2, vLLM, PyTorch DDP) with direct P2P on Broadwell-EP:

```bash
# Enable P2P across the Broadwell Host Bridge
export NCCL_P2P_LEVEL=PHB

# Recommended diagnostic and performance tuning
export NCCL_DEBUG=INFO
export NCCL_BUFFSIZE=8388608
```
