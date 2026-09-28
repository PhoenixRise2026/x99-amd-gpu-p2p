# RCCL P2P Topology & Optimization on Intel Broadwell

## Overview

RCCL (ROCm Communication Collectives Library) is AMD's collective communication library (derived from NVIDIA NCCL). In distributed tensor parallel inference (such as SGLang TP2), AllReduce operations occur at every transformer layer, making inter-GPU bandwidth and latency a critical bottleneck.

When two GPUs are attached to different Root Ports under the same host bridge, RCCL must classify the topology distance and decide whether to establish direct P2P rings/trees or fall back to staging through host memory.

---

## Topology Levels in RCCL

RCCL classifies the interconnect distance between pairs of GPUs using hierarchical levels:

| Level | Identifier | Description | Relative Speed |
| :--- | :--- | :--- | :--- |
| **LOC** | `PATH_LOC` | Same GPU / loopback | Internal VRAM |
| **NVL** | `PATH_NVL` | Dedicated high-speed fabric (xGMI / NVLink) | Highest |
| **PIX** | `PATH_PIX` | Traversal through a single PCIe Switch | Very High (~PCIe line rate) |
| **PXB** | `PATH_PXB` | Traversal through multiple PCIe Switches | High |
| **PHB** | `PATH_PHB` | Traversal through PCIe Host Bridge / Root Complex | High (~10–12 GB/s on PCIe 3.0 x16) |
| **SYS** | `PATH_SYS` | Traversal through system memory / QPI / UPI / NUMA | Low (~2–3 GB/s host fallback) |

On a single-socket Intel X99 / Broadwell-EP system, GPU 0 (`05:00.0`) and GPU 1 (`08:00.0`) reside under separate Root Ports (`00:02.0` and `00:03.0`) of the same Host Bridge (`00:00.0` `8086:6f00`). Therefore, the physical topology level is **`PATH_PHB`**.

---

## The Role of `NCCL_P2P_LEVEL`

By default, RCCL may conservatively disable P2P or demote the maximum permitted P2P level to `PATH_PXB` or `PATH_SYS` if:
1. The platform is not an officially certified AMD multi-GPU platform (e.g. non-EPYC, non-xGMI).
2. The kernel reports host bridge limitations.

Setting:
```bash
export NCCL_P2P_LEVEL=PHB
```
informs RCCL that transfers crossing the PCIe Host Bridge are permitted to use direct P2P DMA rather than falling back to host memory bounce buffers.

---

## RCCL Graph Patch: Honor Explicit `NCCL_P2P_LEVEL`

### The Issue in Stock RCCL 7.2.0

In upstream RCCL (`src/graph/paths.cc`), `ncclGetUserP2pLevel(&p2pLevel)` was called before evaluating platform and architecture constraints:
```cpp
  int p2pLevel = PATH_SYS;

  // User override was queried here in stock code:
  // NCCLCHECK(ncclGetUserP2pLevel(&p2pLevel));

  if (p2pLevel == PATH_SYS) {
    p2pLevel = PATH_PXB;
  }
```
Because the `PATH_SYS` -> `PATH_PXB` clamp occurred *after* querying the environment, an explicit user configuration like `NCCL_P2P_LEVEL=PHB` (or `SYS`) could be overridden back to `PATH_PXB` (level 3). On systems where dual GPUs reside across distinct root ports under the same host bridge (`PATH_PHB` / `PATH_SYS`), this demotion forced RCCL to fall back to SHM staging.

### The Fix

The patch `patches/rccl/0001-graph-honor-explicit-p2p-level-after-platform-limit.patch` relocates `ncclGetUserP2pLevel(&p2pLevel)` to execute *after* the default clamp, ensuring explicit user override requests take precedence:

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

---

## Benchmarking Collectives: `rccl-tests`

We benchmark collective AllReduce performance across message sizes from 8 MB to 1 GB using `rccl-tests`:

```bash
# Execute benchmark via the automated script:
./scripts/run-rccl.sh
```

### Measured Performance Comparison

| Metric | Stock Host Fallback (`PATH_SYS`) | Direct P2P (`PATH_PHB` + Kernel Whitelist) | Improvement |
| :--- | :--- | :--- | :--- |
| **AllReduce Bus Bandwidth (128 MB)** | 2.76 GB/s | **9.49 GB/s** | **+243.8% (3.44x)** |
| **AllReduce Bus Bandwidth (256 MB)** | 2.81 GB/s | **9.52 GB/s** | **+238.8% (3.39x)** |
| **Transport Protocol** | Ring (Host Memory Staging) | Direct P2P Ring (PCIe DMA-BUF) | Direct peer memory access |
| **Host CPU RAM Traffic** | High (memory saturation) | Zero host RAM copies | Host RAM decoupled |

---

## Recommended Production Environment

To run distributed workloads (e.g. SGLang TP2, vLLM, PyTorch DDP) with direct P2P:

```bash
# Enable P2P across the Broadwell Host Bridge
export NCCL_P2P_LEVEL=PHB

# Recommended diagnostic and performance tuning
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,ENV,GRAPH
export NCCL_BUFFSIZE=8388608
```
