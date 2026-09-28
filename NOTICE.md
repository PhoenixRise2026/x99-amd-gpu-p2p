# Notice

This project contains documentation, diagnostic scripts, patch files, and sanitized benchmark data demonstrating PCIe Peer-to-Peer (P2P) enablement between AMD GPUs on Intel Broadwell-EP / X99 platforms.

### Third-Party Code and Patches
1. **Linux Kernel Patches**:
   - Derived from the Linux Kernel (`drivers/pci/p2pdma.c`).
   - Licensed under GPL-2.0-only.
2. **RCCL Patches**:
   - Derived from AMD ROCm RCCL (`src/graph/paths.cc`).
   - Copyright (c) 2015-2020 NVIDIA CORPORATION. All rights reserved.
   - Modifications Copyright (c) 2019-2026 Advanced Micro Devices, Inc. All rights reserved.
   - Modifications Copyright (c) Microsoft Corporation.
   - Licensed under BSD-3-Clause / MIT.
3. **SGLang Case-Study References**:
   - Case-study documentation references external SGLang and community RDNA4 patchsets (e.g. Patch 065). This repository does NOT copy or distribute third-party SGLang source code (Copied code = NO).
   - Upstream references: SGLang Team & Matt Bucci (Apache-2.0).

All original documentation and diagnostic scripts authored in this repository are licensed under MIT (see `LICENSE`).
See `LICENSES/README.md` and `third_party/README.md` for complete licensing and attribution details.
