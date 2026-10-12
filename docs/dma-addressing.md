# DMA Addressing, ReBAR, and IOMMU Evidence

This document separates enumerated hardware facts and successful transfer observations from the not-yet-traced address-translation mechanism. The full evidence ledger is in [High-address P2P investigation](high-address-p2p-investigation.md).

## FACT: reference hardware and DMA mask

The sanitized reference capture records two AMD Radeon AI PRO R9700 devices:

| GPU | BDF | BAR0 aperture | Size |
| --- | --- | --- | ---: |
| GPU 0 | `0000:05:00.0` | `0x380800000000–0x380fffffffff` | 32 GiB |
| GPU 1 | `0000:08:00.0` | `0x381000000000–0x3817ffffffff` | 32 GiB |

The captured Linux sysfs values report a 44-bit DMA mask for each GPU. The validated Ubuntu 6.8 kernel used the stock AMDGPU mask; it did not carry a custom DMA44 change. The BAR ranges are above the 44-bit address limit. These are separate observations; they do not by themselves show what address the GPU emitted for a peer transaction.

## OBSERVED: tested configuration

With the original Ubuntu 6.8 P2PDMA whitelist patch, stock 44-bit AMDGPU mask, and Intel VT-d Translated configuration, the reference machine completed bidirectional HIP IPC data-integrity cases, peer TransferBench runs, and RCCL AllReduce with logs identifying P2P/IPC. The archived kernel-error sample recorded no new AER or DMAR errors for its reported interval.

This supports the bounded statement that the native 44-bit setup completed these tests in the captured environment. It does not prove every device DMA request used an IOVA below 44 bits or that Translated mode is required on all X99 systems.

## OPEN: end-to-end address mapping chain

The following chain has not been captured as one auditable trace:

1. GPU BAR resource address and size.
2. DMA-BUF export and importer attach.
3. P2PDMA mapping result and any `dma_map_resource()` call.
4. IOMMU mapping input and returned IOVA for this peer resource.
5. GPUVM PTE programmed for the imported peer buffer.
6. Address placed on the PCIe request by the GPU during that transfer.

Prior internal notes quote candidate IOVAs such as `0xfe200000`, `0x8e000000`, `0xfe000000`, and `0x8d000000`. Those values came from private eBPF traces that are not included in this repository with capture scripts, kernel/source provenance, or a reproducible trace. Treat them as `OBSERVED_PRIVATE_NOT_REPRODUCIBLE`, not as public proof of a complete mapping chain.

A 44-bit device DMA mask describes the DMA API constraint. A high PCI BAR address describes a physical resource placement. Without evidence tracing the relevant peer mapping and GPU request, one must not infer that the address placed on the wire equals either value, or that the IOMMU necessarily remapped that request in the expected way.

## Historical DMA48 experiment

A local DMA48 driver experiment was tried and reverted. Its patch and raw results are not part of this repository. It is historical context only, not a validated alternative or a production recommendation. The `dma44` suffix in an old local kernel name is also a historical build label; it does not identify a custom DMA44 patch.

## Practical boundary

Keep the known validated pieces distinct: the kernel whitelist change, stock AMDGPU mask, Translated-mode test configuration, and successful bidirectional application-level tests. For other systems, collect their own PCI resource layout and run the supported diagnostic suite. Do not prescribe `iommu=pt`, a custom DMA mask, or DMA48 from this evidence alone.
