# Troubleshooting & Diagnostic Guide

This guide covers Linux PCIe P2PDMA, HIP IPC, and RCCL observations on Broadwell-EP systems with AMD GPUs. It distinguishes a missing prerequisite from insufficient evidence; an unknown result must remain inconclusive.

## 1. Quick diagnostic

Start with the read-only check:

```bash
./scripts/diagnose.sh
```

It inspects detected GPUs, PCI ancestry, root ports and host-bridge domain, IOMMU indicators, PCIe links, and available kernel error logs. A healthy prerequisite report is not proof that an active peer transfer ran. Use `--full` only when you intend to run the external test binaries:

```bash
./scripts/diagnose.sh --full
```

The script reports `DIRECT_P2P_READY = YES` only when its prerequisites, bidirectional transfer evidence, HIP IPC integrity output, RCCL direct-transport markers, and kernel health checks all pass. Missing tools or incomplete evidence result in SKIP or INCONCLUSIVE.

## 2. P2PDMA or peer-transfer check fails

Confirm the running kernel's `drivers/pci/p2pdma.c` contains the Broadwell-EP `8086:6f00` entry with `REQ_SAME_HOST_BRIDGE`, and confirm the two GPU branches are under different root ports in the same host-bridge domain. The PCI whitelist entry allows the Linux P2PDMA topology gate; it does not by itself prove a selected runtime transport or successful data integrity.

The retained [Ubuntu 6.8 validated patch](../patches/linux/validated/0001-pci-p2pdma-add-broadwell-6f00-host-bridge.patch) is scoped to its documented base. Upstream status is tracked in [upstream-status.md](upstream-status.md); maintainer application is not the same as a released kernel.

## 3. TransferBench result is incomplete

The parser requires valid positive bandwidth measurements for both GPU0→GPU1 and GPU1→GPU0. It recognizes TransferBench matrix/flat output, the formats described in the [ROCm preset documentation](https://rocm.docs.amd.com/projects/TransferBench/en/docs-1.66.03/reference/presets.html), and accepts CSV only when the exact bandwidth column is named in the header. CPU-only transfers, GPU self-transfers, malformed or unlabeled CSV, and one-way-only results cannot produce PASS. Inspect the original output and confirm the binary's format before interpreting an INCONCLUSIVE result.

GFX Pull's approximately 3.14 GB/s GPU0→GPU1 result is an observation from the archived run. The opposite direction is not present, and the cause of its difference from SDMA/Push has not been established.

## 4. HIP IPC result is incomplete

The wrapper requires explicit read and write verification in both GPU directions. A successful exit status without those lines is INCONCLUSIVE. If the external binary is missing, the wrapper reports SKIP; CI uses a fixture binary and never runs on a real GPU.

## 5. RCCL falls back or lacks transport evidence

Set `NCCL_DEBUG=INFO` and inspect the logs for both `isAllDirectP2p 1` and `via P2P/IPC`. An AllReduce completing with exit code 0, or a line containing a generic “P2P” phrase, does not prove that both GPUs used the direct transport.

The local RCCL patch is tied to the `rocm-7.2.0` / RCCL 2.27.7 source baseline. The reference runtime result used a patched library. Current `develop` source and released 7.2.x source status are summarized in [RCCL documentation](rccl.md); verify the actual source revision and library before applying a compatibility patch. Do not infer that every current or future RCCL release needs it.

## 6. High BAR addresses, 44-bit mask, and IOMMU

The reference capture shows BAR0 ranges above the 44-bit mask and a reported stock 44-bit DMA mask. It also records successful tests with VT-d Translated mode. The repository does not capture the complete mapping from peer BAR through DMA-BUF, DMA API/IOMMU, GPUVM, and the GPU's PCIe request.

Therefore:
- A BAR address above the device mask is a reason to investigate addressability, not proof of the address used for each DMA request.
- The successful Translated-mode run is an observed configuration, not proof that every peer access was remapped into a particular IOVA range.
- Do not assert that `iommu=pt` necessarily causes truncation or that Translated mode is a universal requirement based only on these artifacts.
- Keep the old DMA48 trial as historical context; do not deploy a custom DMA mask based on it.

See [DMA addressing](dma-addressing.md) and the [high-address investigation](high-address-p2p-investigation.md) for the evidence ledger.

## 7. PCIe ACS and other topology issues

If peer transfers fail or time out, inspect PCIe ancestry and the ACS capabilities shown by `lspci -vv`. ACS redirection, firmware layout, bridge configuration, and runtime support can affect peer routing. Diagnose the exact system before changing BIOS settings or kernel parameters; do not disable ACS globally as a generic fix.

## 8. Verification checklist

- [ ] Confirm both GPUs and their distinct root ports share the same `8086:6f00` host-bridge domain.
- [ ] Confirm the kernel patch/source revision and the RCCL source/library revision.
- [ ] In an intentional hardware run, collect complete bidirectional TransferBench and HIP IPC evidence.
- [ ] Confirm RCCL logs show `isAllDirectP2p 1` and `via P2P/IPC`.
- [ ] Record the time interval and source of AER/DMAR/GPU-reset log checks.
- [ ] Keep hardware results separate from the offline tests; CI does not establish GPU or product acceptance.
