# Architecture Overview: Dual AMD R9700 P2P on Intel Broadwell-EP / X99

## High-Level System Architecture

```text
+-------------------------------------------------------------------------+
|                  Intel Xeon E5-2697A v4 (Broadwell-EP)                  |
|                        Single-Socket, 16C / 32T                         |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  |           PCIe Host Bridge / Root Complex Domain [8086:6f00]       |  |
|  |           (Kernel P2PDMA Whitelist: REQ_SAME_HOST_BRIDGE)         |  |
|  +---------------------------------+---------------------------------+  |
|                                    |                                    |
|             Root Port 2            |             Root Port 3            |
|             [8086:6f04]            |             [8086:6f08]            |
|          PCIe 3.0 x16 Link         |          PCIe 3.0 x16 Link         |
+------------------------------------+------------------------------------+
                                     |
                                     v
                    +----------------------------------+
                    | Direct Cross-Root-Port P2P Path  |
                    | ~10.29 GB/s SDMA (Per-Direction) |
                    +----------------------------------+
                                     |
                  +------------------+------------------+
                  |                                     |
                  v                                     v
    +---------------------------+         +---------------------------+
    |    AMD PCIe Bridge Func   |         |    AMD PCIe Bridge Func   |
    |        [1002:1478]        |         |        [1002:1478]        |
    |        [1002:1479]        |         |        [1002:1479]        |
    +-------------+-------------+         +-------------+-------------+
                  |                                     |
                  v                                     v
    +---------------------------+         +---------------------------+
    |   AMD Radeon AI PRO R9700 |         |   AMD Radeon AI PRO R9700 |
    |        (0000:05:00.0)     |         |        (0000:08:00.0)     |
    |     32 GiB GDDR6 ReBAR    |         |     32 GiB GDDR6 ReBAR    |
    |   Physical: 0x380800000000|         |   Physical: 0x381000000000|
    |   IOVA:     0x00008e000000|         |   IOVA:     0x00008d000000|
    +---------------------------+         +---------------------------+
```

## Architectural Building Blocks

1. **Host Interconnect (Intel Broadwell-EP Ring Bus)**:
   - On the single-socket Xeon E5-2697A v4, PCIe lanes for both full-bandwidth x16 slots are routed directly to Root Ports 2 and 3 on the CPU uncore.
   - P2P memory traffic traverses the internal CPU switch ring without staging in host DDR4 RAM.
2. **IOMMU Address Translation (Intel VT-d Translated)**:
   - The system operates with VT-d enabled in Translated mode (`DMA-FQ`).
   - Peer memory requests are remapped via `dma_map_resource()` into compact IOVA space (< 4 GiB), ensuring that physical 46-bit BAR addresses are accessible within the stock 44-bit DMA mask of AMDGPU. *(Observed during private validation; raw trace not distributed in v0.1. Note that Translated mode was required on this specific reference testbed due to 64-bit BAR placement; requirements on other X99 systems depend on motherboard BAR mapping.)*
3. **P2PDMA Whitelist Clearance (`p2pdma.c`)**:
   - The Linux PCI core verifies that Host Bridge `8086:6f00` is whitelisted.
   - `calc_map_type_and_dist()` returns `PCI_P2PDMA_MAP_THRU_HOST_BRIDGE` rather than `PCI_P2PDMA_MAP_NOT_SUPPORTED`, allowing DMA-BUF mapping across root ports.
4. **Transport Layer (HIP IPC & RCCL)**:
   - User-space applications utilize HIP IPC for zero-copy cross-process buffer sharing (`HSA_ENABLE_IPC_MODE_LEGACY=0` on the reference stack).
   - Collective operations run via a patched RCCL library with `NCCL_P2P_LEVEL=PHB`, enabling direct GPU-to-GPU AllReduce over the PCIe bus without falling back to host shared memory (SHM).
