# Architecture Overview: Dual AMD R9700 P2P on Intel Broadwell-EP / X99

## Observed reference topology

```text
Intel Xeon E5-2697A v4 / Broadwell-EP
Host bridge: 8086:6f00
  ├─ Root Port 0000:00:02.0
  │    └─ AMD bridge functions → R9700 GPU 0, 0000:05:00.0
  │         BAR0: 0x380800000000–0x380fffffffff (32 GiB)
  └─ Root Port 0000:00:03.0
       └─ AMD bridge functions → R9700 GPU 1, 0000:08:00.0
            BAR0: 0x381000000000–0x3817ffffffff (32 GiB)
```

The sanitized PCI capture records the device IDs and resource ranges above. The two GPUs report a stock 44-bit DMA mask in the captured sysfs data. The reference workload used Ubuntu 6.8 with the repository's `8086:6f00` P2PDMA whitelist patch and VT-d Translated mode.

## What the evidence shows

The reference run includes bidirectional HIP IPC integrity results, per-direction TransferBench results, and RCCL logs showing `isAllDirectP2p 1` and `via P2P/IPC`. Those results support successful P2P operation for this tested system and configuration. See [high-address investigation](high-address-p2p-investigation.md) for the evidence limits and [the manifest](../results/evidence-manifest.json) for artifact hashes.

## What the diagram does not claim

BAR resource addresses are not presented as IOVAs in this diagram. The repository does not contain a reproducible, end-to-end capture of DMA-BUF attachment, `dma_map_resource()`, the IOMMU output mapping, the peer buffer's GPUVM PTE, and the actual GPU DMA request address. Do not treat an inferred mapping or private trace as proof of that chain.

The P2PDMA whitelist addresses the Linux PCI topology/map-type gate. HIP IPC and RCCL logs report application/runtime behavior. Those are distinct layers; success at one layer does not by itself prove the mechanism at every other layer.
