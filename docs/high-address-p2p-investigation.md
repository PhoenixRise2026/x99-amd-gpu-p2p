# High-address P2P Investigation

Last evidence review: **2026-10-12**. This document re-evaluates the reference X99/Broadwell-EP and dual-R9700 evidence already stored in this repository. It records no new hardware experiment.

## Scope and evidence labels

- **FACT**: directly present in source, system enumeration, or an artifact.
- **OBSERVED**: a result recorded in a sanitized run artifact.
- **INFERENCE**: a plausible explanation supported by partial evidence, with a missing link stated.
- **OPEN**: not established by the public artifacts.

## FACT: reference platform

The reference system is an Intel Xeon E5-2697A v4 host with bridge `8086:6f00`, and two AMD Radeon AI PRO R9700 GPUs at `0000:05:00.0` and `0000:08:00.0`. The PCI capture places their 32 GiB BAR0 apertures at `0x380800000000–0x380fffffffff` and `0x381000000000–0x3817ffffffff`. The captured sysfs DMA mask is 44 bits for both GPUs. The tested kernel is Ubuntu 6.8.0-139 with the repository's Broadwell P2PDMA whitelist patch; the tested IOMMU setting is Intel VT-d Translated.

These values establish resource placement and the configured device mask. They do not identify the address used by a particular peer DMA transaction.

## OBSERVED: transfer and application results

- HIP IPC evidence records six of six configured transfer/integrity cases passing across both GPU directions.
- TransferBench records approximately 10.29 GB/s for SDMA and GFX Push in each direction. GFX Pull records approximately 3.14 GB/s for GPU0 to GPU1 in the available capture; the reverse Pull measurement is absent.
- RCCL output reports `isAllDirectP2p 1` and `via P2P/IPC`. Its largest reported AllReduce bus bandwidth is about 9.49 GB/s.
- The archived kernel-error capture reports no AER or DMAR fault in its sampled interval.

These observations demonstrate that the tested native 44-bit configuration completed the recorded bidirectional P2P correctness/performance workloads without errors in the captured interval. RCCL bus bandwidth and TransferBench's directional copy rate are different metrics. Application logs alone do not expose the full PCIe address path.

## INFERENCE: why Translated mode may matter here

The captured BAR0 locations are above the 44-bit DMA-mask limit, while successful tests were run with VT-d Translated. It is reasonable to investigate whether a mapped DMA address made the peer BAR reachable under this configuration. The artifacts do not isolate Translated mode as the cause, show a controlled passthrough comparison, or capture all mappings and GPU requests. Therefore “Translated mode fixed the high-address access” remains an inference for this host, not a demonstrated universal mechanism or X99 requirement.

## OPEN: missing proof across the mapping chain

No public artifact in this repository connects all of these stages for a single transfer:

1. Peer BAR physical resource.
2. DMA-BUF export and importer attach.
3. Linux P2PDMA map-type decision and any `dma_map_resource()` input/result.
4. IOMMU IOVA mapping for that resource.
5. GPUVM PTE for the imported peer address.
6. Actual DMA request address observed at the GPU/PCIe boundary.

Old internal notes name IOVAs `0xfe200000`, `0x8e000000`, `0xfe000000`, and `0x8d000000`. The eBPF trace, exact collection procedure, and matching kernel/source provenance are not distributed here. These are private, non-reproducible observations and cannot prove that every peer request used one of those addresses.

Also open: whether a given failure under passthrough is caused by a DMA mask rejection, IOMMU mapping behavior, GPUVM programming, firmware resource placement, or another layer. The existing logs do not distinguish those mechanisms.

## Historical DMA48 experiment

An experimental 48-bit mask modification was reportedly tried and reverted. The source diff, complete test results, and production acceptance record are absent from this repository. It is historical context only; this project does not recommend deploying it. “Native DMA44 passed the recorded workload” does not imply that a 48-bit modification is necessary or safe.

## Reproduction boundary

Publicly reproducible from this repository: offline diagnostic/parser tests and inspection of the sanitized evidence files. Reproducing the hardware results requires the named class of Broadwell-EP host, dual R9700 devices, matching software stack, and external HIP IPC / TransferBench / RCCL test binaries. CI does not execute those tools or access GPUs. See [the evidence manifest](../results/evidence-manifest.json) for hashes, versions, and test conditions.
