# Troubleshooting & Diagnostic Guide

This guide covers common issues encountered when enabling PCIe P2PDMA, HIP IPC, and RCCL collective acceleration across Intel Broadwell-EP host bridges (`8086:6f00`) and AMD RDNA4 GPUs.

---

## 1. Quick Automated Health Check

Always begin by running the non-destructive diagnostic script:

```bash
./scripts/diagnose.sh
```

A healthy system will report:
```text
=== Overall Assessment ===
[PASS] Host bridge 8086:6f00 is present
[PASS] GPUs are under distinct Root Ports of the same Host Bridge
[PASS] PCIe links running at expected speed/width
[PASS] IOMMU active (Translated mode)
[PASS] 0 PCIe AER / DMAR errors detected
DIRECT_P2P_READY = YES
```

If any checks fail, follow the troubleshooting procedures below.

---

## 2. Issue: TransferBench / HIP IPC Falls Back to Host Memory

### Symptoms
- TransferBench bidirectional bandwidth is capped at ~2.5–3.0 GB/s.
- `hipDeviceCanAccessPeer()` returns `0`.
- Kernel logs contain messages rejecting P2PDMA distance calculation.

### Root Cause
The running kernel does not have the Intel Broadwell Host Bridge (`8086:6f00`) in the `pci_p2pdma_whitelist[]` table in `drivers/pci/p2pdma.c`. Linux defaults to marking unlisted host bridges as `PCI_P2PDMA_NOT_CALCULATED` or `PCI_P2PDMA_THROUGH_HOST_BRIDGE` disallowed.

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
- `rccl-tests` reports AllReduce bus bandwidth around ~2.76 GB/s instead of ~9.5 GB/s.
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
- AMD RDNA4 (gfx1201) hardware page tables support up to 44-bit physical address space (`DMA_BIT_MASK(44)`).
- On Intel platforms with >64 GB RAM, physical RAM addresses can exceed `0x0000_0FFF_FFFF_FFFF` (44 bits).
- Under Intel VT-d **Translated mode** (`intel_iommu=on`), the IOMMU remaps memory into a compact 39-bit or 44-bit IOVA domain, preventing 48-bit DMA truncation.
- Under **Passthrough mode** (`iommu=pt`), physical addresses above 44-bit are not remapped and will cause silent truncation or DMAR faults.

### Resolution
- Keep Intel VT-d enabled in translated mode.
- Avoid passing `iommu=pt` or `amd_iommu=pt` on architectures requiring sub-48-bit DMA constraints.
- Note: Stock AMDGPU drivers already enforce 44-bit masks; do not attempt experimental 48-bit kernel hacks.

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
- In Linux, verify `pci=noacs` only if supported and required by the platform firmware.

---

## 6. Verification Checklist

Before deploying production distributed workloads, verify:
- [ ] `./scripts/diagnose.sh` reports `DIRECT_P2P_READY = YES`.
- [ ] `./scripts/run-transferbench.sh` achieves ~10.29 GB/s bidirectional P2P.
- [ ] `./scripts/check-hip-ipc.sh` completes 100% PASS with 0 memory errors.
- [ ] `./scripts/run-rccl.sh` achieves ~9.49 GB/s AllReduce bus bandwidth.
- [ ] `./scripts/collect-errors.sh` confirms 0 AER / DMAR / amdgpu errors.
