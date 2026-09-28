# x99-amd-gpu-p2p

**Linux P2PDMA, Direct HIP IPC & RCCL Collective Acceleration on Intel Broadwell-EP (X99) with AMD RDNA4 GPUs**

---

## Overview

This repository provides verified patches, diagnostic scripts, architecture documentation, and empirical benchmarks enabling **direct hardware Peer-to-Peer (P2P) PCIe DMA transfers** between AMD GPUs across Intel Broadwell-EP (X99) Root Complexes.

Historically, Linux kernel PCIe P2PDMA allowed Haswell-EP host bridges (`8086:2f00` / `8086:2f01`) to perform peer DMA across root ports, but the Broadwell-EP successor (`8086:6f00`) was omitted from the upstream whitelist. Consequently, multi-GPU AMD ROCm workloads (such as distributed LLM inference with SGLang / vLLM using RCCL) were marked `PCI_P2PDMA_MAP_NOT_SUPPORTED`, forcing inter-GPU communication to fall back to host shared memory staging (`via SHM/direct/direct`).

By adding `8086:6f00` to the Linux P2PDMA whitelist and ensuring proper IOMMU translation, direct peer transfers achieve **~10.29 GB/s per direction** in TransferBench and **9.49 GB/s** in RCCL AllReduce with zero kernel AER/DMAR faults.

---

## Verified Empirical Metrics

All performance figures below are strictly locked to verifiable raw test evidence:

| Benchmark | Stock Baseline | Direct P2P (This Repo) | Metric Description | Raw Evidence Source |
| :--- | :--- | :--- | :--- | :--- |
| **TransferBench P2P (SDMA/Push)** | Fallback / Rejected | **10.29 GB/s** | Per-direction unidirectional bandwidth | `examples/broadwell-r9700/transferbench.txt` |
| **RCCL Ring AllReduce (256–1024 MiB)**| Fallback to SHM | **9.49 GB/s** | Bus bandwidth ($B_{\text{bus}} = B_{\text{alg}}$) | `examples/broadwell-r9700/rccl.txt` |
| **HIP IPC Cross-Process Sharing** | Fallback / Rejected | **Direct DMA-BUF Map** | 1M, 16M, 64M bidirectional correctness | `examples/broadwell-r9700/hip-ipc.txt` |
| **SGLang Qwen3.8 TP2 (C=1 Decode)** | 30.93 tok/s (via SHM) | **31.28 tok/s** (Direct P2P) | Single-request autoregressive decode | `results/x99-r9700-qwen38.md` |
| **SGLang Qwen3.8 TP2 (C=4 Decode)** | 69.41 tok/s (via SHM) | **71.10 tok/s** (Direct P2P) | Concurrency 4 aggregate decode | `results/x99-r9700-qwen38.md` |
| **Kernel Bus Stability** | 0 errors | **0 errors** | Zero AER errors, zero DMAR faults | `examples/broadwell-r9700/kernel-errors.txt` |

*Reference Platform: Single Intel Xeon E5-2697A v4 (Broadwell-EP), 2x AMD Radeon AI PRO R9700 (RDNA4 gfx1201), ROCm 7.2.4, Ubuntu 24.04 / Kernel 6.8.*

---

## Key Technical Clarifications

1. **Kernel DMA Mask & "dma44"**:
   The validated kernel **does not contain a custom 44-bit DMA patch**. AMDGPU natively uses its stock `DMA_BIT_MASK(44)`. The string `dma44` in historical local kernel build tags was retained solely as a build milestone identifier from an earlier experiment where an unstable 48-bit DMA hack was tested and reverted. No custom GMC driver modification is needed or used.
2. **IOMMU Addressing & Causality**:
   Intel VT-d must be enabled in **Translated mode** (`intel_iommu=on`). The 44-bit DMA address space covers up to 16 TiB ($2^{44}-1$ bytes). The risk on 64-bit systems arises when firmware or kernel MMIO windows allocate GPU BAR resources into high 64-bit address space. Under Translated mode, the IOMMU dynamically remaps peer accesses into compact IOVAs, ensuring addresses remain within the 44-bit DMA mask.
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
│   │   └── upstream/       # Candidate patch prepared for Linux mainline git
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
│   └── sglang-qwen38-case-study.md # Verified inference case study
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
├── results/                # Detailed benchmark logs and tables
│   └── x99-r9700-qwen38.md # SGLang Qwen3.8-27B-AWQ TP2 benchmark results
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
OVERALL: P2P_PREREQUISITES = PASS
OVERALL: DIRECT_P2P_READY = INCONCLUSIVE (run with --full to execute peer benchmarks)
```

To run active peer benchmarks (TransferBench, HIP IPC, and RCCL) and gate full P2P readiness:
```bash
./scripts/diagnose.sh --full
```

---

## Applying the Kernel Patch

### Validated Patch (Kernel 6.8.x)

If running Ubuntu 24.04 or standard Linux 6.8.x:
```bash
cd /usr/src/linux-source-6.8.0 # or your kernel tree
git apply /path/to/x99-amd-gpu-p2p/patches/linux/validated/0001-pci-p2pdma-add-broadwell-6f00-host-bridge.patch
```

### Upstream Linux Mainline Candidate

A candidate patch prepared for upstream `torvalds/linux` master is provided at:
`patches/linux/upstream/0001-PCI-P2PDMA-Allow-P2PDMA-through-Intel-Broadwell-host-bridge.patch`.
- Rebased on `torvalds/linux` master commit `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`.
- Passed `checkpatch.pl --strict` (0 errors, 0 warnings).
- Maintainers identified via `get_maintainer.pl`.
- **Status**: Candidate patch prepared for future upstream submission. Functional validation must be performed on the reference Broadwell-EP `8086:6f00` host or an equivalent topology.

---

## Configuring RCCL for Direct P2P

In ROCm 7.2.0+, export the P2P level to allow transfers across the PCIe Host Bridge:

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
- [SGLang Qwen3.8-27B Inference Case Study](docs/sglang-qwen38-case-study.md)

---

## License & Attribution

- Original project documentation, scripts, and results are licensed under the [MIT License](LICENSE).
- Linux kernel patches are licensed under `GPL-2.0-only` (see [LICENSES/README.md](LICENSES/README.md)).
- RCCL patches are derivative diffs against `src/graph/paths.cc` subject to the upstream BSD-3-Clause license, copyright (c) Advanced Micro Devices, Inc., and NVIDIA Corporation.
