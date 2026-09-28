# x99-amd-gpu-p2p

**Linux P2PDMA, Direct HIP IPC & RCCL Collective Acceleration on Intel Broadwell-EP (X99) with AMD RDNA4 GPUs**

---

## Overview

This repository provides verified patches, diagnostic scripts, architecture documentation, and empirical benchmarks enabling **direct hardware Peer-to-Peer (P2P) PCIe DMA transfers** between AMD GPUs across Intel Broadwell-EP (X99) Root Complexes.

Historically, Linux kernel PCIe P2PDMA allowed Haswell-EP host bridges (`8086:2f00` / `8086:2f01`) to perform peer DMA across root ports, but the Broadwell-EP successor (`8086:6f00`) was omitted from the upstream whitelist. Consequently, multi-GPU AMD ROCm workloads (such as distributed LLM inference with SGLang / vLLM using RCCL) silently fell back to copying data through system DRAM (`PATH_SYS`), severely throttling inter-GPU AllReduce bandwidth to ~2.76 GB/s.

By adding `8086:6f00` to the Linux P2PDMA whitelist and ensuring proper IOMMU translation, direct peer transfers achieve **10.29 GB/s** in TransferBench and **9.49 GB/s** in RCCL AllReduce—a **+243.8% (3.44x) throughput gain** with zero kernel AER/DMAR faults.

---

## Verified Headline Metrics

| Benchmark | Stock Host Fallback | Direct P2P (This Repo) | Improvement | Test Status |
| :--- | :--- | :--- | :--- | :--- |
| **TransferBench P2P Bandwidth** | 2.5–3.0 GB/s (Host staging) | **10.29 GB/s** | **+243% (~3.4x)** | Verified (0 errors) |
| **RCCL AllReduce Bus Bandwidth** | 2.76 GB/s (`PATH_SYS`) | **9.49 GB/s** (`PATH_PHB`) | **+243.8% (3.44x)** | Verified (0 errors) |
| **HIP IPC Peer Sharing** | Fallback / Rejected | **Direct DMA-BUF Map** | **100% PASS** | Verified (0 errors) |
| **SGLang Qwen3.8-27B TP2 TTFT** | 342.1 ms | **289.0 ms** | **-15.5% latency** | Verified |
| **SGLang Qwen3.8-27B TP2 Decode**| 41.2 tok/s | **58.7 tok/s** | **+42.5% throughput**| Verified |
| **PCIe AER / DMAR Faults** | 0 errors | **0 errors** | **100% Stable** | Verified |

*Hardware: Intel Xeon E5-2697A v4 (Broadwell-EP), 2x AMD Radeon AI PRO R9700 (RDNA4 gfx1201), ROCm 7.2.0, Ubuntu 24.04 / Kernel 6.8.*

---

## Key Technical Clarifications

To avoid common misconceptions and clarify historical artifacts:

1. **Kernel DMA Mask & "dma44"**:
   The validated kernel **does not contain a custom 44-bit DMA patch**. AMDGPU natively uses its stock `DMA_BIT_MASK(44)`. The string `dma44` in historical local kernel build tags is merely a build name from an earlier experiment where an unstable 48-bit DMA hack was tested and reverted. No custom GMC driver modification is needed or used.
2. **IOMMU Addressing**:
   Intel VT-d must be enabled in **Translated mode** (`intel_iommu=on`). The IOMMU remaps GPU DMA into a 39-bit or 44-bit IOVA domain, ensuring compatibility with the RDNA4 hardware address space without silent 48-bit truncation.
3. **AITER Status**:
   In our validated SGLang v0.5.18 environment, `AITER_ACTIVE = NO`. Decode runs via optimized ROCm Composable Kernel (CK) backends. This is a software deployment configuration, not a hardware limitation of RDNA4.
4. **PCIe Switch Device String**:
   On R9700 cards, `lspci` displays an internal bridge labeled `"Navi 10 XL Upstream/Downstream Port of PCI Express Switch (1002:1478/1479)"`. This is a legacy PCI ID database text label for the on-board PCIe switch; the GPU core itself is RDNA4 gfx1201.

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
│   │   ├── validated/      # Patch applied and validated on Ubuntu 6.8.0-139
│   │   └── upstream/       # Candidate patch prepared for Linux mainline git
│   └── rccl/               # Patch for ROCm 7.2.0 RCCL graph P2P override
├── docs/                   # Deep-dive architecture and troubleshooting docs
│   ├── architecture.md     # Hardware & software architecture
│   ├── topology.md         # PCIe Root Complex topology analysis
│   ├── broadwell-p2pdma.md # Linux P2PDMA whitelist deep dive
│   ├── dma-addressing.md   # IOMMU, DMA masks, and IOVA translation
│   ├── hip-ipc.md          # HIP IPC validation methodology
│   ├── rccl.md             # RCCL topology detection and P2P tuning
│   ├── troubleshooting.md  # Comprehensive diagnostic guide
│   └── sglang-qwen38-case-study.md # Real-world inference case study
├── scripts/                # Automated non-destructive inspection tools
│   ├── diagnose.sh         # Master read-only diagnostic tool
│   ├── collect-topology.sh # Collects tree and device BDF topology
│   ├── check-pcie.sh       # Verifies link speed, width, and ACS
│   ├── check-dma-addresses.sh # Inspects DMA mask and IOMMU groups
│   ├── check-hip-ipc.sh    # Compiles and runs bidirectional HIP IPC test
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

Clone or copy this repository, and run the automated read-only diagnostic check:

```bash
chmod +x scripts/*.sh
./scripts/diagnose.sh
```

The script will inspect your PCIe topology, check for Host Bridge `8086:6f00`, evaluate IOMMU translation, check link speeds, and determine if your platform is ready for direct P2P.

Expected output:
```text
=== Overall Assessment ===
[PASS] Host bridge 8086:6f00 is present
[PASS] GPUs are under distinct Root Ports of the same Host Bridge
[PASS] PCIe links running at expected speed/width
[PASS] IOMMU active (Translated mode)
[PASS] 0 PCIe AER / DMAR errors detected
DIRECT_P2P_READY = YES
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

A cleanly rebased patch for upstream `torvalds/linux` master is provided at:
`patches/linux/upstream/0001-PCI-P2PDMA-Allow-P2PDMA-through-Intel-Broadwell-host-bridge.patch`.
- Passed `checkpatch.pl` (0 errors, 0 warnings).
- Maintainers identified via `get_maintainer.pl`.
- Note: Provided as a release candidate for community review; not yet submitted upstream.

---

## Configuring RCCL for Direct P2P

In ROCm 7.2.0+, export the P2P level to allow transfers across the PCIe Host Bridge:

```bash
export NCCL_P2P_LEVEL=PHB
export NCCL_DEBUG=INFO
```

Run `rccl-tests` to verify:
```bash
./scripts/run-rccl.sh
```

---

## Documentation Index

- [Architecture Overview](file:///docs/architecture.md)
- [PCIe Topology Analysis](file:///docs/topology.md)
- [Broadwell P2PDMA Whitelist Details](file:///docs/broadwell-p2pdma.md)
- [IOMMU & DMA Addressing Guide](file:///docs/dma-addressing.md)
- [HIP IPC Validation](file:///docs/hip-ipc.md)
- [RCCL Collective Acceleration](file:///docs/rccl.md)
- [Diagnostic & Troubleshooting Guide](file:///docs/troubleshooting.md)
- [SGLang Qwen3.8-27B Inference Case Study](file:///docs/sglang-qwen38-case-study.md)

---

## Upstream Status

- **Linux Mainline (`torvalds/linux` `master`)**: Checked against commit `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e` (September 2026). Broadwell `8086:6f00` is currently absent from `drivers/pci/p2pdma.c`. The upstream patch candidate is ready for submission and community review.
- **RCCL**: ROCm 7.2.0 benefits from `NCCL_P2P_LEVEL=PHB`. A patch addressing internal platform limit overrides is documented in `patches/rccl/`.

---

## License

This project is licensed under the MIT License. See [LICENSE](file:///LICENSE) and [LICENSES/README.md](file:///LICENSES/README.md) for details.
Kernel patches are licensed under GPL-2.0-only as per Linux kernel licensing requirements.
