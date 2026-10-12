# System & Runtime Version Provenance Matrix

This document records the version and revision provenance for the reference-system captures. It is scoped to the archived test configuration, not a compatibility guarantee. Upstream status last checked 2026-10-12.

---

## Hardware Platform

| Component | Identifier | Model / Revision Details |
| :--- | :--- | :--- |
| **CPU** | Intel Xeon E5-2697A v4 | Broadwell-EP, 16 Cores / 32 Threads @ 2.60 GHz, Single-socket (Socket 0) |
| **Host Bridge** | `8086:6f00` | Intel Xeon E7 v4/Xeon E5 v4/Xeon E3 v4/Xeon D DMI2 Host Bridge (devfn 00.0) |
| **Root Ports** | `8086:6f04` / `8086:6f08` | Root Port 2 (`0000:00:02.0`) & Root Port 3 (`0000:00:03.0`) |
| **GPUs** | `1002:7551` | 2x AMD Radeon AI PRO R9700 (32 GiB GDDR6 each, PCIe 3.0 x16 @ 8.0 GT/s) |
| **GPU Bridge** | `1002:1478` / `1002:1479` | AMD PCIe bridge/switch function (PCI ID label: "Navi 10 XL") |
| **System RAM** | 128 GB | 4x 32 GB DDR4-2400 ECC Registered |

---

## Operating System & Kernel Stack

| Component | Reported Version / Tag | Base Source / Commit SHA | Notes |
| :--- | :--- | :--- | :--- |
| **Operating System** | Ubuntu 24.04.1 LTS | Linux Foundation Ubuntu Kernel Tree | Standard server distribution |
| **Running Kernel** | `6.8.12-r9700-p2p-dma44` | Base `Ubuntu-6.8.0-139.139` (`78d7d3da9419bebf9c91d65c6268db56a705445e`) | Patched with `8086:6f00` P2PDMA whitelist entry. Stock 44-bit DMA mask. |
| **Mainline Kernel Status**| Linux 7.3-rc6 listed | [Kernel.org](https://www.kernel.org/), checked 2026-10-12 | `8086:6f00` patch reported applied to `pci/p2pdma` for v7.4, but absent from current Linus tree; no released kernel confirmed |
| **IOMMU State** | Intel VT-d Translated (`DMA-FQ`) | Reference capture / kernel command line | Tested configuration; exact peer IOVA mapping and GPU request-address chain are not publicly traced |

---

## Driver & ROCm Runtime Stack

| Component | Reported Version | Build / Package Identifier | Notes |
| :--- | :--- | :--- | :--- |
| **Kernel Driver (AMDGPU)**| ROCK DKMS `6.16.13` | Module SHA256: `dfab6f8d6c54fab1658766f469967190a419f6aa09c832352998d1ba95fe88c5` | Stock `DMA_BIT_MASK(44)` |
| **ROCm Runtime** | `7.2.4` | `dpkg -l rocm-core` / `hipcc` | System ROCm package release |
| **RCCL Runtime** | `2.27.7` | `librccl.so.1.0` (SHA256: `8caa0dfd7a8b504a49864e6bad4b20e4ac326c57731cd627c4985022dbe24d04`) | Reference library includes the local PHB override change; exact binary is not redistributed |
| **RCCL Source Base Tag** | `rocm-7.2.0` | Commit `0d2c4fd4c5ea8aa96b4ac4eb468fb4146ab2c921` | Local patch is version-scoped; release/develop review is summarized in [RCCL compatibility notes](rccl.md) |
| **Triton Runtime** | `3.6.0` | Python package `triton==3.6.0` | **ACTIVE** for attention, GDN, and AWQ GEMM |
| **AITER Runtime** | None / Absent | `AITER_ACTIVE = NO` | Not installed; not used in validated inference stack |

---

## Inference Application Stack

| Component | Reported Version | Base Commit / Artifact SHA | Notes |
| :--- | :--- | :--- | :--- |
| **SGLang** | `v0.5.18` | Base `71de97b26` / Tested `07eb3ec8` | Tensor Parallelism (TP=2) serving engine |
| **Model Artifact** | `shawnw3i/Qwen3.8-27B-AWQ-MTP` | Safetensors INT4 AWQ (Base: Qwen3.8-27B) | 64 Layers, group size 64, hybrid DeltaNet + Attention |
| **Attention Backend** | `triton` | Native SGLang Triton backend | `--attention-backend triton` |
| **Full Attention** | Triton | Native Triton attention kernels | Prefill / decode attention path |
| **Recurrent Path (GDN)** | Triton | `torch_triton_sequential_recurrent` | Hybrid recurrent state path |
| **AWQ GEMM ($M > 1$)** | Triton | `triton_awq_gemm` | Batched AWQ GEMM |
| **AWQ GEMV ($M = 1$)** | Native HIP | `awq_gemv_bf16_hip` | Single-token decode kernel |
| **MTP Tree-Verify** | Triton | `tree_verify_attention_fwd` | Multi-token prediction verification kernel |
