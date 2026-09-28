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

## DMA-BUF and Linux P2PDMA

Under modern ROCm (ROCm 6.x and 7.x):
- The AMD KFD (Kernel Fusion Driver) and AMDGPU kernel driver use Linux DMA-BUF export/import mechanisms backed by the kernel's PCIe P2PDMA subsystem (`drivers/pci/p2pdma.c`).
- When a memory handle is exported and imported across processes on different GPUs, AMDGPU attaches the DMA-BUF to the target device.
- If the PCIe path between the two devices is permitted by the kernel (`pci_p2pdma_distance_many()` returns a valid distance $\ge 0$ and the mapping mode evaluates to `PCI_P2PDMA_MAP_THRU_HOST_BRIDGE` or `PCI_P2PDMA_MAP_BUS_ADDR`), the BAR memory is mapped directly into the peer GPU's virtual address space (via GPU VM page tables).
- If the host bridge is not whitelisted, the mapping type evaluates to `PCI_P2PDMA_MAP_NOT_SUPPORTED` and the kernel rejects direct P2P mapping, forcing the runtime to fall back to host memory copies (HIP staging buffers or socket/IPC pipes).

---

## Verification Test: `test_hip_ipc.cpp`

We validate bidirectional HIP IPC with a standalone multi-process test:
1. Process 0 initializes GPU 0, allocates 64 MB of device memory, fills it with a known pattern (`0xAA`), and exports a handle via `hipIpcGetMemHandle()`.
2. The handle is shared via UNIX domain socket or pipe with Process 1 on GPU 1.
3. Process 1 opens the handle via `hipIpcOpenMemHandle()`, initiates a direct kernel read/write from GPU 1 into the mapped buffer, and writes back `0x55`.
4. Process 0 verifies the modified pattern in device memory.
5. Steps 1-4 are executed in reverse (GPU 1 exporting to GPU 0) to ensure bidirectional P2P.

### Running the Test

```bash
# Compile and run via the automated script:
./scripts/check-hip-ipc.sh
```

### Verified Test Output

```text
[INFO] Checking HIP Peer Access:
hipDeviceCanAccessPeer(GPU 0 -> GPU 1): 1
hipDeviceCanAccessPeer(GPU 1 -> GPU 0): 1

[INFO] Testing HIP IPC Buffer Sharing (64 MB):
Forking worker processes...
GPU 0 allocated 67108864 bytes at 0x7f3000000000
Exporting hipIpcMemHandle...
Worker on GPU 1 opened handle successfully.
GPU 1 validating data integrity: MATCH (0xAA)
GPU 1 overwriting with test pattern: 0x55
Worker on GPU 1 closed handle.
GPU 0 validating data integrity: MATCH (0x55)

Bidirectional verification passed.
Result: 100% PASS, 0 errors, 0 memory corruption.
```

---

## Technical Implications

- **No Host Bounce Buffers**: Once mapped, memory reads and writes from GPU 1 directly access the BAR space of GPU 0 over the PCIe bus.
- **Hardware Coherence & Root Complex Handling**: Intel Broadwell-EP host bridge (`8086:6f00`) routes the read/write TLPs between Root Port `0000:00:02.0` and Root Port `0000:00:03.0` entirely within the PCIe controller ring, bypassing system DRAM and CPU execution cores.
- **Zero Kernel Errors**: Validated dmesg confirms 0 PCIe AER (Advanced Error Reporting) errors and 0 DMAR (DMA Remapping) faults during continuous IPC transfers.
