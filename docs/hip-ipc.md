# HIP IPC Validation on AMD RDNA4 (gfx1201)

## Overview

In multi-GPU PyTorch, SGLang, and distributed training/inference stacks, peer communication within a single node relies on direct GPU-to-GPU memory sharing via Inter-Process Communication (IPC) handles. On AMD ROCm, this is exposed through HIP IPC APIs:

- `hipIpcGetMemHandle()`: Exports an allocated device buffer into an opaque `hipIpcMemHandle_t`.
- `hipIpcOpenMemHandle()`: Imports the remote memory handle into the calling process address space.
- `hipIpcCloseMemHandle()`: Unmaps and releases the imported buffer.

For direct peer memory operations to function without routing through host RAM bounce buffers, two prerequisites must be satisfied:
1. **Peer Accessibility**: `hipDeviceCanAccessPeer(&canAccess, dev0, dev1)` must return `canAccess = 1`.
2. **PCIe Root Complex P2P Capability**: The host bridge connecting the root ports must allow Peer-to-Peer PCIe transactions (enabled via the Linux kernel P2PDMA whitelist for Intel Broadwell `8086:6f00`).

---

## DMA-BUF and Linux P2PDMA boundary

The Linux P2PDMA whitelist is one kernel topology/mapping gate in the tested setup. The exact KFD, AMDGPU, DMA-BUF, DMA API, and GPUVM path depends on the kernel and ROCm source revisions. The public artifacts in this repository do not trace a single imported peer buffer through DMA-BUF attach, `dma_map_resource()`, the IOMMU output, the GPUVM PTE, and the GPU's PCIe request. Do not infer that complete path from a successful HIP IPC check or the whitelist entry alone.

The archived HIP IPC output verifies content read/write patterns across the two process/device directions. It is evidence of successful application-level peer sharing in that tested configuration; it does not by itself identify every lower-level mapping or prove a general fallback behavior when the kernel prerequisite is absent. See [high-address P2P investigation](high-address-p2p-investigation.md).

---

## External Verification Binary (`EXTERNAL_DEPENDENCY`)

The standalone cross-process HIP IPC validation binary used during hardware testing is treated as an external dependency and is not distributed in v0.1. Its source provenance is from external ROCm HIP sample test harnesses (exact upstream commit: UNKNOWN).

The test methodology validates bidirectional HIP IPC with a multi-process architecture:
1. Process 0 initializes GPU 0, allocates device memory (1M, 16M, and 64M tiers), fills it with a known pattern, and exports a handle via `hipIpcGetMemHandle()`.
2. The handle is shared with Process 1 on GPU 1.
3. Process 1 opens the handle via `hipIpcOpenMemHandle()`, performs direct kernel verification, and writes back a verification pattern.
4. Process 0 verifies the modified pattern in device memory.
5. Steps 1-4 are executed in reverse (GPU 1 exporting to GPU 0) to ensure bidirectional P2P.

### Running the Test

Pass an existing external HIP IPC validation binary:
```bash
./scripts/check-hip-ipc.sh --binary /path/to/hip_ipc_binary
```
If no binary is supplied or found, the script exits cleanly with code `2` (`SKIP` / `INCONCLUSIVE`). Note: The historical HIP IPC reproducer binary/source is not distributed in v0.1.

### Verified Test Output (Excerpt from `examples/broadwell-r9700/hip-ipc.txt`)

```text
DIRECTION: GPU 0 (Exporter) -> GPU 1 (Importer)
--------------------------------------------------------------------------------
[Test 1] 1 MiB (1,048,576 bytes)
  Forward Read Verify:  PASS (Pattern matches expected bitmask)
  Reverse Write Verify: PASS (Pattern matches expected bitmask)
  Hardware Health:      0 DMAR faults, 0 AER errors

[Test 2] 16 MiB (16,777,216 bytes)
  Forward Read Verify:  PASS (Pattern matches expected bitmask)
  Reverse Write Verify: PASS (Pattern matches expected bitmask)
  Hardware Health:      0 DMAR faults, 0 AER errors

[Test 3] 64 MiB (67,108,864 bytes)
  Forward Read Verify:  PASS (Pattern matches expected bitmask)
  Reverse Write Verify: PASS (Pattern matches expected bitmask)
  Hardware Health:      0 DMAR faults, 0 AER errors

DIRECTION: GPU 1 (Exporter) -> GPU 0 (Importer)
--------------------------------------------------------------------------------
[Test 4] 1 MiB (1,048,576 bytes)   -> PASS (0 DMAR / 0 AER)
[Test 5] 16 MiB (16,777,216 bytes) -> PASS (0 DMAR / 0 AER)
[Test 6] 64 MiB (67,108,864 bytes) -> PASS (0 DMAR / 0 AER)

Summary:
- Cross-process P2P memory access verified in both directions across all sizes.
- Zero kernel faults (0 DMAR / 0 AER) during memory handle transactions.
```

---

## Technical Implications

- **Transport inference**: The HIP IPC integrity log shows cross-process sharing succeeded. RCCL separately reports `via P2P/IPC` for its direct run. Neither log is a PCIe TLP trace, so avoid claims about every transaction bypassing host memory unless supported by lower-level instrumentation.
- **Root-complex topology**: PCI enumeration places the GPUs under different Root Ports of the same `8086:6f00` host-bridge domain. The exact internal routing/coherence behavior is not measured by the included logs.
- **Bounded kernel-error sample**: The archived log reports zero AER/DMAR faults for its sampled interval. It does not establish an error-free guarantee for arbitrary duration or other workloads.
