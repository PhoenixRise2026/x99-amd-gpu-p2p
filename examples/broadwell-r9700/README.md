# Sanitized Reference Benchmarks & Diagnostics: Intel Broadwell-EP + Dual R9700

## Environment Context
* **Platform**: HUANANZHI X99-TF GAMING V6.0
* **CPU**: Intel Xeon E5-2697A v4 @ 2.60GHz (Single-socket Broadwell-EP)
* **Host Bridge**: `8086:6f00` (devfn 00.0)
* **GPUs**: Dual AMD Radeon AI PRO R9700 (32 GiB GDDR6, gfx1201)
  * GPU 0: `0000:05:00.0` (Root Port 2 `0000:00:02.0`)
  * GPU 1: `0000:08:00.0` (Root Port 3 `0000:00:03.0`)
* **Kernel**: Linux `6.8.12-r9700-p2p-dma44` (with `8086:6f00` P2PDMA whitelist entry)
* **Driver**: ROCK DKMS 6.16.13 (AMDGPU stock 44-bit DMA mask)
* **IOMMU**: Intel VT-d Translated (`DMA-FQ`)
* **ROCm**: 7.2.4

## File Index
1. `topology.txt`: Complete PCIe bus hierarchy from root complex to endpoints.
2. `lspci.txt`: Detailed PCI configuration, BAR memory allocations, and capabilities.
3. `transferbench.txt`: TransferBench peer-to-peer throughput matrix (SDMA and GFX Push/Pull).
4. `hip-ipc.txt`: Cross-process standalone HIP IPC verification logs across 1M, 16M, and 64M transfers.
5. `rccl.txt`: RCCL AllReduce collective bandwidth sweep (1M to 1024M).
6. `real_llm_tp2_stock_vs_p2p_ab_results.json`: Complete raw JSON trace of real LLM TP=2 inference benchmark (Stock SHM vs Direct P2P).
7. `kernel-errors.txt`: Post-benchmark kernel journal error audit verifying zero faults.

All logs in this directory have been sanitized: private home directories and internal hostnames have been replaced with standard generic tokens (`$HOME` and `reference-host`), while preserving all hardware metrics and numeric benchmark outputs intact.
