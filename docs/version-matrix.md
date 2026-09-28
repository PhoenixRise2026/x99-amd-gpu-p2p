# System & Runtime Version Provenance Matrix

This document provides the definitive version and revision mapping for all hardware, kernel, driver, runtime, library, and inference framework components used in the reference system validation.

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
| **Mainline Kernel Target**| Linux 7.3-rc5 | `torvalds/linux.git` `master` (`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`) | Upstream rebase target for candidate patch |
| **IOMMU State** | Translated (`DMA-FQ`) | Kernel commandline `intel_iommu=on` | Dynamic 32/44-bit IOVA allocation |

---

## Driver & ROCm Runtime Stack

| Component | Reported Version | Build / Package Identifier | Notes |
| :--- | :--- | :--- | :--- |
| **Kernel Driver (AMDGPU)**| ROCK DKMS `6.16.13` | Module SHA256: `dfab6f8d6c54fab1658766f469967190a419f6aa09c832352998d1ba95fe88c5` | Stock `DMA_BIT_MASK(44)` |
| **ROCm Runtime** | `7.2.4` | `dpkg -l rocm-core` / `hipcc` | System ROCm package release |
| **RCCL Runtime** | `2.27.7` | `librccl.so.1.0` (SHA256: `8caa0dfd7a8b504a49864e6bad4b20e4ac326c57731cd627c4985022dbe24d04`)| Patched with PHB user override fix |
| **RCCL Source Base Tag** | `rocm-7.2.0` | Commit `0d2c4fd4c5ea8aa96b4ac4eb468fb4146ab2c921` | Base repository: `https://github.com/ROCm/rccl` |
| **Triton Runtime** | `3.6.0` | Python package `triton==3.6.0` | **ACTIVE** for attention, GDN, and AWQ GEMM |
| **AITER Runtime** | None / Absent | `AITER_ACTIVE = NO` | Not installed; not used in validated inference stack |

---

## Inference Application Stack

| Component | Reported Version | Base Commit / Artifact SHA | Notes |
| :--- | :--- | :--- | :--- |
| **SGLang** | `v0.5.18` | Base `71de97b26` / Tested `07eb3ec8` | Tensor Parallelism (TP=2) serving engine |
| **Model** | `Qwen3.8-27B-AWQ-MTP` | Safetensors INT4 AWQ | 64 Layers, group size 64, hybrid DeltaNet + Attention |
| **Attention Backend** | `triton` | Native SGLang Triton backend | `--attention-backend triton` |
| **Full Attention** | Triton | `tree_verify_attention_fwd` | Triton-based verification kernel |
| **Recurrent Path (GDN)** | Triton | `torch_triton_sequential_recurrent` | Hybrid recurrent state path |
| **AWQ GEMM ($M > 1$)** | Triton | `triton_awq_gemm` | Batched AWQ GEMM |
| **AWQ GEMV ($M = 1$)** | Native HIP | `awq_gemv_bf16_hip` | Single-token decode kernel |
