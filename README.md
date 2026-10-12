# x99-amd-gpu-p2p

English | [简体中文](README.zh-CN.md)

**Linux P2PDMA, Direct HIP IPC & RCCL Collective Acceleration on Intel Broadwell-EP (X99) with AMD RDNA4 GPUs**

---

## Overview

This repository records the Linux P2PDMA change, diagnostic tools, architecture evidence, and benchmark results for **direct GPU Peer-to-Peer (P2P) PCIe transfers** across Root Ports under an Intel Broadwell-EP host bridge. The v0.2.0 maintenance update distinguishes upstream status, the reference-hardware observations, and mechanisms that remain unproven.

On 2026-10-07, the Linux PCI maintainer reported the `8086:6f00` P2PDMA patch applied to the `pci/p2pdma` development tree for the v7.4 merge window. At the 2026-10-12 check, it was not yet present in Linus' current mainline tree or a released kernel. See [upstream status](docs/upstream-status.md); maintainer application is not a merge or release.

The reference Ubuntu 6.8 system with the local whitelist patch, stock 44-bit AMDGPU mask, and VT-d Translated configuration recorded **~10.29 GB/s per direction** for TransferBench SDMA/Push and **~9.49 GB/s** RCCL Rank-2 AllReduce bus bandwidth. These are different metrics and workload layers. The BARs are above the reported 44-bit mask, but the repository does not capture the full DMA-BUF → IOMMU → GPUVM → PCIe request address chain. The successful test does not prove a particular IOVA mapping or a universal IOMMU requirement; see [high-address P2P investigation](docs/high-address-p2p-investigation.md).

---

## Verified Empirical Metrics

All performance figures below are strictly locked to verifiable raw test evidence:

| Benchmark | Stock Baseline | Direct P2P (This Repo) | Metric Description | Raw Evidence Source |
| :--- | :--- | :--- | :--- | :--- |
| **TransferBench P2P (SDMA/Push)** | Not included in public evidence | **10.29 GB/s** | Per-direction unidirectional bandwidth | `examples/broadwell-r9700/transferbench.txt` |
| **RCCL Ring AllReduce (256–1024 MiB)**| See SGLang A/B logs for SHM transport | **9.49 GB/s** | Rank-2 bus bandwidth; not one-way peer-copy rate | `examples/broadwell-r9700/rccl.txt` |
| **HIP IPC Cross-Process Sharing** | Not included in public evidence | **Bidirectional content integrity** | 1 MiB, 16 MiB, 64 MiB cases | `examples/broadwell-r9700/hip-ipc.txt` |
| **SGLang Qwen3.8 TP2 (C=1 Decode)** | 30.93 tok/s (via SHM) | **31.28 tok/s** (Direct P2P) | Single-request autoregressive decode | `results/x99-r9700-qwen38.md` |
| **SGLang Qwen3.8 TP2 (C=4 Decode)** | 69.41 tok/s (via SHM) | **71.10 tok/s** (Direct P2P) | Concurrency 4 aggregate decode | `results/x99-r9700-qwen38.md` |
| **Kernel Error Sample** | No paired baseline | **0 observed** | No AER/DMAR faults in the archived interval | `examples/broadwell-r9700/kernel-errors.txt` |

*Reference Platform: Single Intel Xeon E5-2697A v4 (Broadwell-EP), 2x AMD Radeon AI PRO R9700 (RDNA4 gfx1201), ROCm 7.2.4, Ubuntu 24.04 / patched Ubuntu 6.8. Prefill A/B results are mixed: +32.1% at 1K, −3.7% at 4K, +0.5% at 16K, and +25.5% at 32K medians; see [full ranges and trial counts](results/x99-r9700-qwen38.md).*

---

## Key Technical Clarifications

1. **Kernel DMA Mask & "dma44"**:
   The validated kernel **does not contain a custom 44-bit DMA patch**. AMDGPU natively uses its stock `DMA_BIT_MASK(44)`. The string `dma44` in historical local kernel build tags was retained solely as a build milestone identifier from an earlier experiment where an unstable 48-bit DMA hack was tested and reverted. No custom GMC driver modification is needed or used.
2. **IOMMU Addressing & Causality**:
   The reference captures show BAR0 above the reported stock 44-bit DMA mask and record successful P2P tests while VT-d was Translated. The artifacts do not trace the peer DMA-BUF mapping through the IOMMU, GPUVM, and actual GPU request address. Translated mode is the tested configuration; its exact role and requirements on other systems remain open. See [DMA evidence](docs/dma-addressing.md).
3. **AITER & Runtime Backend**:
   AITER is not installed or active (`AITER_ACTIVE = NO`) in the validated SGLang v0.5.18 environment. The validated decode stack is mixed Triton/HIP (Full Attention: Triton; GDN/recurrent: Triton; Tree-Verify: Triton; AWQ M>1: Triton; AWQ M=1: native HIP GEMV). This describes the validated software stack only and should not be interpreted as a hardware support limitation for AITER on gfx1201.
4. **PCIe Bridge Device String**:
   In `lspci`, the bridge functions `1002:1478/1479` may display the label `"Navi 10 XL Upstream/Downstream Port of PCI Express Switch"`. The "Navi 10 XL" string is simply the PCI ID database label for the AMD PCIe bridge/switch function `1002:1478/1479` and does not describe the R9700 GPU architecture (which is RDNA4 gfx1201).
5. **Topology Classification vs Transport**:
   `PATH_PHB` is a topology distance classification. When direct P2P eligibility is rejected, RCCL falls back to the `SHM` transport. With the RCCL override patch and `NCCL_P2P_LEVEL=PHB`, RCCL grants P2P eligibility and selects `via P2P/IPC`.

---

## Repository Structure

```text
x99-amd-gpu-p2p/
├── README.md               # This document
├── LICENSE                 # MIT License
├── NOTICE.md               # Legal and third-party notices
├── SECURITY.md             # Security policy and reporting
├── CONTRIBUTING.md         # Contribution and review guidelines
├── LICENSES/               # Component-specific license details
├── patches/
│   ├── linux/
│   │   ├── validated/      # Patch validated on Ubuntu 6.8.0-139
│   │   └── upstream/       # Maintainer-applied patch status and history
│   └── rccl/               # Patch for ROCm 7.2.0 RCCL graph P2P override
├── docs/                   # Architecture, topology, and analysis docs
│   ├── architecture.md     # Hardware & software architecture
│   ├── topology.md         # PCIe Root Complex topology analysis
│   ├── broadwell-p2pdma.md # Linux P2PDMA whitelist deep dive
│   ├── dma-addressing.md   # IOMMU, DMA masks, and IOVA translation
│   ├── hip-ipc.md          # HIP IPC validation methodology
│   ├── rccl.md             # RCCL topology detection and P2P tuning
│   ├── troubleshooting.md  # Comprehensive diagnostic guide
│   ├── version-matrix.md   # Complete software and hardware version matrix
│   ├── sglang-qwen38-case-study.md # Verified inference case study
│   ├── upstream-status.md  # Dated Linux PCI/P2PDMA status
│   └── high-address-p2p-investigation.md # DMA44 evidence and open questions
├── results/
│   ├── x99-r9700-qwen38.md # Full SGLang A/B ranges
│   └── evidence-manifest.json # Artifact hashes and evidence limits
├── tests/                  # Offline fail-closed and evidence validation
├── .github/workflows/      # Offline-only CI
├── RELEASE_NOTES_v0.2.0.md # Draft; no tag or release created
├── scripts/                # Automated non-destructive inspection tools
│   ├── diagnose.sh         # Fail-closed diagnostic tool
│   ├── collect-topology.sh # Collects tree and device BDF topology
│   ├── check-pcie.sh       # Verifies link speed, width, and ACS
│   ├── check-dma-addresses.sh # Inspects DMA mask and IOMMU groups
│   ├── check-hip-ipc.sh    # HIP IPC verification wrapper
│   ├── run-transferbench.sh # Runs TransferBench P2P bandwidth test
│   ├── run-rccl.sh         # Runs rccl-tests AllReduce benchmark
│   └── collect-errors.sh   # Inspects dmesg for AER, DMAR, or GPU resets
├── examples/               # Sanitized reference outputs from validated server
│   └── broadwell-r9700/    # Reference logs from Intel Broadwell + 2x R9700
└── third_party/            # Upstream provenance and license tracking
```

---

## Quick Start: Diagnostic Inspection

Clone or copy this repository, and run the fail-closed diagnostic check:

```bash
chmod +x scripts/*.sh
./scripts/diagnose.sh
```

By default, `diagnose.sh` inspects platform prerequisites (CPU socket, host bridge `8086:6f00`, distinct root ports, IOMMU translated mode, link parameters, and error counters). If active peer transfers have not yet been executed, it reports:
```text
P2P_PREREQUISITES = PASS
DIRECT_P2P_READY = INCONCLUSIVE
```

To run active peer benchmarks (TransferBench, HIP IPC, and RCCL) and gate full P2P readiness:
```bash
./scripts/diagnose.sh --full
```

---

## Applying the Kernel Patch

### Validated Patch (`Ubuntu-6.8.0-139.139`)

This patch is validated specifically on `Ubuntu-6.8.0-139.139` (Kernel `6.8.12`, Git SHA: `78d7d3da9419bebf9c91d65c6268db56a705445e`). Other kernel versions require rebasing and independent validation:
```bash
git apply patches/linux/validated/0001-pci-p2pdma-add-broadwell-6f00-host-bridge.patch
```

### Linux upstream status

The maintainer reported the patch applied to `pci/p2pdma` for v7.4. At the 2026-10-12 check it was not in current Linus mainline or a released kernel. The original Ubuntu 6.8 validated patch remains separately preserved. See [upstream status](docs/upstream-status.md) and [`patches/linux/upstream/`](patches/linux/upstream/README.md).

---

## Configuring Direct P2P: Readiness Gates

Direct P2P AllReduce requires clearing three distinct layers (validated on the reference Broadwell-EP + RCCL `2.27.7` / `rocm-7.2.0` testbed):

1. **Platform Addressability (Reference System Scope)**:
   - The reference records high BAR placement, a stock 44-bit device DMA mask, and successful tests with Intel VT-d Translated. The complete address mapping path has not been captured; do not extrapolate the configuration to other systems.
2. **Kernel Subsystem Gate**:
   - Intel Broadwell-EP `8086:6f00` must be present in the Linux kernel `pci_p2pdma_whitelist[]` (`drivers/pci/p2pdma.c`) with `REQ_SAME_HOST_BRIDGE`.
3. **RCCL User-Space Graph Gate**:
   - The local compatibility patch targets RCCL 2.27.7 / `rocm-7.2.0` source. The exact development and release status was checked separately; see [RCCL version notes](docs/rccl.md).
   - For a build that requires the patch, verify that `NCCL_P2P_LEVEL=PHB` and the logs show direct P2P markers:
   ```bash
   export NCCL_P2P_LEVEL=PHB
   export NCCL_DEBUG=INFO
   ```

---

## Documentation Index

- [Architecture Overview](docs/architecture.md)
- [PCIe Topology Analysis](docs/topology.md)
- [Broadwell P2PDMA Whitelist Details](docs/broadwell-p2pdma.md)
- [IOMMU & DMA Addressing Guide](docs/dma-addressing.md)
- [HIP IPC Validation](docs/hip-ipc.md)
- [RCCL Collective Acceleration](docs/rccl.md)
- [Diagnostic & Troubleshooting Guide](docs/troubleshooting.md)
- [Version & Provenance Matrix](docs/version-matrix.md)
- [Linux Upstream Status](docs/upstream-status.md)
- [High-address P2P Investigation](docs/high-address-p2p-investigation.md)
- [Evidence Manifest](results/evidence-manifest.json)
- [v0.2.0 Release Notes Draft](RELEASE_NOTES_v0.2.0.md)
- [SGLang Qwen3.8-27B Inference Case Study](docs/sglang-qwen38-case-study.md)

---

## License & Attribution

- Original project documentation, scripts, and results are licensed under the [MIT License](LICENSE).
- Linux kernel patches are licensed under `GPL-2.0-only` (see [LICENSES/README.md](LICENSES/README.md)).
- RCCL patches are derivative diffs against `src/graph/paths.cc` subject to the upstream BSD-3-Clause license, copyright (c) Advanced Micro Devices, Inc., and NVIDIA Corporation.
