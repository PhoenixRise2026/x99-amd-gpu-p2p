# DMA Addressing, ReBAR, and IOMMU Modes

## 1. Stock AMDGPU DMA Mask (FACT)
* In the official AMDGPU driver source (`drivers/gpu/drm/amd/amdgpu/gmc_v12_0.c` line 803):
  ```c
  r = dma_set_mask_and_coherent(adev->dev, DMA_BIT_MASK(44));
  ```
* Both AMD Radeon AI PRO R9700 GPUs report a 44-bit DMA mask in Linux sysfs:
  ```text
  /sys/bus/pci/devices/0000:05:00.0/dma_mask_bits = 44
  /sys/bus/pci/devices/0000:08:00.0/dma_mask_bits = 44
  ```
* **The validated kernel does not contain a custom 44-bit DMA patch.**
* AMDGPU uses its stock 44-bit DMA mask out of the box.

---

## 2. ReBAR Placement (FACT)
On platforms with Resizable BAR enabled for dual 32 GiB GPUs, the system firmware assigns BAR0 apertures above the 4 TiB boundary:
* GPU 0 (`05:00.0`): `0x380800000000 - 0x380fffffffff` (32 GiB, ReBAR)
* GPU 1 (`08:00.0`): `0x381000000000 - 0x3817ffffffff` (32 GiB, ReBAR)

These physical addresses require 46 physical address bits ($\text{bit 45} = 1$).

---

## 3. Physical Address vs IOMMU Translated Address (INFERENCE & FACT)

### The Passthrough Mode Failure (`iommu=pt`)
* Under `iommu=pt` (passthrough mode), DMA addresses map directly 1:1 to physical bus addresses.
* Because the peer BAR sits at 46-bit physical addresses (`0x3808...`), a GPU with a 44-bit DMA mask ($2^{44}-1 = \text{0x00000FFFFFFFFFFF}$) cannot directly address it without truncation or out-of-bounds rejection.
* AMDGPU's internal peer accessibility check (`aper_base & ~address_mask != 0`) evaluates to false, causing P2P negotiation to fail.

### The VT-d Translated Mode Solution (`DMA-FQ`)
* On the reference system, Intel VT-d is enabled in **Translated mode** (the default Linux behavior when `iommu=pt` is absent).
* When peer memory is attached via `dma_map_resource()`, the Intel IOMMU translates the target BAR into an IOVA.
* Dynamic eBPF tracing confirmed that the IOMMU allocator assigns IOVAs within 32-bit address space:
  * GPU0 mapping GPU1 BAR: IOVA returned is `0xfe200000` / `0x8e000000` (32-bit).
  * GPU1 mapping GPU0 BAR: IOVA returned is `0xfe000000` / `0x8d000000` (32-bit).
* Because $32 \le 44$, all peer DMA transactions fall strictly within the GPU's stock 44-bit DMA mask.
* **Result**: Zero DMAR faults, zero AER errors, and 100% data integrity with stock AMDGPU driver code.

---

## 4. Historical 48-bit Experiment (HISTORICAL EXPERIMENT)
* During early research, an experimental driver modification (`dma48.patch`) was tested, changing `DMA_BIT_MASK(44)` to `DMA_BIT_MASK(48)` in `gmc_v12_0.c`.
* While this allowed peer checks to pass in passthrough mode, it introduced potential driver and swiotlb inconsistencies.
* Once VT-d Translated mode was verified to naturally map IOVAs into 32-bit space, **the experimental 48-bit modification was completely reverted**.
* The label "dma44" in the validated kernel build name was retained solely as a historical test milestone identifier to record that native 44-bit DMA was confirmed functional.

---

## 5. Current Validated State Summary
The functional, production-stable configuration consists of:
1. **Intel Broadwell `8086:6f00` P2PDMA whitelist patch** in the Linux kernel;
2. **Stock AMDGPU 44-bit DMA mask** (no driver patch);
3. **Intel VT-d in Translated mode** (`DMA-FQ`, standard default without `iommu=pt`).
