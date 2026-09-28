# Third-Party Attributions & Provenance

This project references and derives minimal patchsets from several upstream open-source software stacks. Below is the comprehensive provenance matrix:

| Project | Upstream URL | Reference Commit / Tag | Upstream License | Copied Code? | Modified? | Purpose in this Project | Attribution |
| :--- | :--- | :--- | :--- | :---: | :---: | :--- | :--- |
| **Linux Kernel** | `https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git` | `Ubuntu-6.8.0-139` (`78d7d3da9`) / Mainline `72d3fcf80` | GPL-2.0-only | NO (Patch only) | YES | Adds Intel Broadwell-EP `8086:6f00` to `pci_p2pdma_whitelist[]`. | Linux Kernel Organization & Contributors |
| **ROCm RCCL** | `https://github.com/ROCm/rccl` | `rocm-7.2.0` (`0d2c4fd4c`) / `develop` (`8fc1528f4`) | BSD-3-Clause | NO (Patch only) | YES | Restores user override priority for `NCCL_P2P_LEVEL=PHB`. Derived diff against `src/graph/paths.cc`. | AMD, NVIDIA Corporation, Microsoft Corporation |
| **AMD TransferBench** | `https://github.com/ROCm/TransferBench` | ROCm 7.x (`EXACT_REVISION = UNKNOWN`, `PROVENANCE_PARTIAL`) | MIT | NO | NO | P2P transfer throughput benchmarking tool. | Advanced Micro Devices, Inc. |
| **RCCL Tests** | `https://github.com/ROCm/rccl-tests` | ROCm 7.x (`EXACT_REVISION = UNKNOWN`, `PROVENANCE_PARTIAL`) | BSD-3-Clause | NO | NO | Collective AllReduce performance sweep utility. | Advanced Micro Devices, Inc. |
| **SGLang** | `https://github.com/sgl-project/sglang` | `v0.5.18` (`71de97b26`) / Tested (`07eb3ec8`) | Apache-2.0 | NO | NO | Base LLM serving runtime framework. | SGLang Team & Contributors |
| **RDNA4 SGLang Community Patches** | `https://github.com/mattbucci/2x-R9700-RDNA4-GFX1201-sglang-inference` | `bde64bd8febfc16b65a39e8555ecbf538a838912` | Apache-2.0 | NO | YES | RDNA4 (gfx1201) model definition, conv1d TP, and Split-KV tree verify (Patch 065). | Matt Bucci & Open Source Community |
