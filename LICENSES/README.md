# Licensing & Multi-License Structure

This repository contains materials under different open-source licenses based on their respective upstream origins:

### 1. Project Documentation and Scripts
- **License**: MIT License (`LICENSE`)
- **Applies to**: `README.md`, `docs/`, `scripts/*.sh`, `examples/**/*.md`, `results/`.

### 2. Linux Kernel Patches
- **License**: GNU General Public License v2.0 only (`GPL-2.0-only`)
- **Applies to**: `patches/linux/**/*.patch`
- **Origin**: Linux kernel (`drivers/pci/p2pdma.c`).

### 3. RCCL Patches
- **License**: BSD 3-Clause License (`BSD-3-Clause`)
- **Applies to**: `patches/rccl/**/*.patch`
- **Origin**: AMD ROCm RCCL project (`src/graph/paths.cc`).

### 4. SGLang Case-Study References
- Case-study documentation references external SGLang and community RDNA4 patches (e.g. Patch 065); this repository does NOT bundle or copy third-party SGLang source files (`Copied code = NO`).
- **Upstream License**: Apache License 2.0 (`Apache-2.0`).
