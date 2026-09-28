# Troubleshooting & Diagnostic Guide

This guide covers common issues encountered when enabling PCIe P2PDMA, HIP IPC, and RCCL collective acceleration across Intel Broadwell-EP host bridges (`8086:6f00`) and AMD RDNA4 GPUs.

---

## 1. Quick Automated Health Check

Always begin by running the non-destructive diagnostic script:

```bash
./scripts/diagnose.sh
```

A healthy system will report prerequisite readiness:
```text
=== Prerequisites Assessment ===
[PASS] Host bridge 8086:6f00 is present
[PASS] GPUs are under distinct Root Ports of the same Host Bridge
[PASS] PCIe links running at expected speed/width
[PASS] IOMMU active (Translated mode)
[PASS] 0 PCIe AER / DMAR errors detected
OVERALL: P2P_PREREQUISITES = PASS
OVERALL: DIRECT_P2P_READY = INCONCLUSIVE (run with --full to execute peer benchmarks)
```

Running `./scripts/diagnose.sh --full` executes active peer benchmarks and confirms full readiness:
```text
OVERALL: DIRECT_P2P_READY = YES
```

If any checks fail, follow the troubleshooting procedures below.

---

## 2. Issue: TransferBench / HIP IPC Falls Back to Host Memory

### Symptoms
- TransferBench peer bandwidth is substantially lower than the validated direct-P2P result.
- `hipDeviceCanAccessPeer()` returns `0`.
- Kernel logs contain messages rejecting P2PDMA distance calculation.

### Root Cause
The running kernel does not have the Intel Broadwell Host Bridge (`8086:6f00`) in the `pci_p2pdma_whitelist[]` table in `drivers/pci/p2pdma.c`. Without this whitelist entry, Linux PCI core rejects peer mapping across root ports (evaluating to `PCI_P2PDMA_MAP_NOT_SUPPORTED`).

### Resolution
1. Verify kernel version:
   ```bash
   uname -r
   ```
2. Apply the validated patch:
   ```bash
   git apply patches/linux/validated/0001-pci-p2pdma-add-broadwell-6f00-host-bridge.patch
   ```
3. Rebuild and boot into the patched kernel.

---

## 3. Issue: RCCL Falls Back to `PATH_SYS`

### Symptoms
- `rccl-tests` reports AllReduce bus bandwidth degraded to host shared memory rates (via SHM fallback) instead of full direct peer bandwidth (~9.49 GB/s).
- With `NCCL_DEBUG=INFO`, logs output:
  ```text
  Channel 00 : 0[0] -> 1[1] [receive] via NET/Socket or Host memory
  P2P direct disabled between dev 0 and dev 1
  ```

### Root Cause
RCCL defaults to disabling inter-Root-Port P2P unless explicitly told to allow traversal across the PCIe Host Bridge (`PATH_PHB`). Furthermore, in unpatched ROCm 7.2.0, hardcoded platform heuristics may clamp the P2P level.

### Resolution
1. Set the environment variable:
   ```bash
   export NCCL_P2P_LEVEL=PHB
   ```
2. If RCCL still refuses P2P under ROCm 7.2.0, apply the patch:
   `patches/rccl/0001-graph-honor-explicit-p2p-level-after-platform-limit.patch` and rebuild `librccl.so`.

---

## 4. Issue: DMAR Faults or DMA Remapping Errors

### Symptoms
- `dmesg` reports:
  ```text
  DMAR: [DMA Read] Request device [05:00.0] fault addr 0x... [fault reason 05]
  ```
- GPU hang, soft lockup, or `amdgpu: GPU reset begin`.

### Diagnostic Steps
Run:
```bash
./scripts/collect-errors.sh
./scripts/check-dma-addresses.sh
```

### Analysis
- AMD RDNA4 (gfx1201) hardware page tables support up to 44-bit physical address space (`DMA_BIT_MASK(44)`), covering up to 16 TiB ($2^{44}-1$ bytes).
- System RAM capacity does not directly cause addresses to exceed 44 bits. However, platform firmware or the kernel PCI resource allocator may assign 64-bit ReBAR apertures into high physical MMIO address windows (e.g. 46-bit physical addresses like `0x3808_0000_0000`).
- Under Intel VT-d **Translated mode** (`intel_iommu=on`), the IOMMU remaps peer memory requests via `dma_map_resource()` into compact 32-bit or 44-bit IOVAs (e.g. `0x0000_8e00_0000`), completely satisfying the GPU's 44-bit DMA mask.
- Under **Passthrough mode** (`iommu=pt`), raw physical BAR addresses (>44-bit) would be directly presented to the GPU DMA engine without remapping, causing DMAR faults or address truncation.

### Resolution
- Maintain Intel VT-d enabled in translated mode (`intel_iommu=on`, `DMA-FQ`).
- Avoid passing `iommu=pt` or `amd_iommu=pt` when 64-bit BARs reside above the 44-bit physical boundary.
- Note: Stock AMDGPU drivers natively enforce 44-bit DMA masks; do not attempt experimental 48-bit kernel modifications.

---

## 5. Issue: PCIe ACS (Access Control Services) Blocking P2P

### Symptoms
- Both cards are recognized, but P2P transfers timeout or return Bus Error.

### Diagnostic
Inspect ACS capability on upstream Root Ports:
```bash
lspci -vvv -s 00:02.0 | grep -i -A 5 "Access Control Services"
lspci -vvv -s 00:03.0 | grep -i -A 5 "Access Control Services"
```
If `SrcValid+`, `TransBlk+`, or `ReqRedir+` are enabled, ACS may prevent peer-to-peer routing between downstream hierarchy branches.

### Resolution
- In motherboard BIOS, configure PCIe ACS to allow peer-to-peer routing or disable Request Redirect between PCIe slots.
- In Linux, as an advanced non-default diagnostic tool, specific ACS request redirection can be tested using the kernel parameter `pci=disable_acs_redir=<pci_dev>` (e.g. target root port BDFs). Do not attempt broad global ACS disabling.

---

## 6. Verification Checklist

Before deploying production distributed workloads, verify:
- [ ] `./scripts/diagnose.sh --full` reports `DIRECT_P2P_READY = YES` (default mode reports `INCONCLUSIVE` until active peer transfers are run).
- [ ] `./scripts/run-transferbench.sh` achieves ~10.29 GB/s per-direction unidirectional peer throughput.
- [ ] `./scripts/check-hip-ipc.sh --binary <path-to-hip-ipc-test>` completes 100% PASS with 0 memory errors (the historical test binary is an external dependency not distributed in v0.1; omitting `--binary` reports SKIP / INCONCLUSIVE).
- [ ] `./scripts/run-rccl.sh --full` achieves ~9.49 GB/s AllReduce bus bandwidth (large message reproduction; `./scripts/run-rccl.sh` performs a quick 64 MiB smoke test).
- [ ] `./scripts/collect-errors.sh` confirms 0 AER / DMAR / amdgpu errors.
