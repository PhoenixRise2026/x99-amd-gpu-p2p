# Sanitized Reference Benchmarks & Diagnostics: Intel Broadwell-EP + Dual R9700

## Captured configuration

- CPU: Intel Xeon E5-2697A v4; host bridge `8086:6f00`.
- GPUs: two AMD Radeon AI PRO R9700, `0000:05:00.0` and `0000:08:00.0`, on separate Root Ports.
- Kernel: Ubuntu 6.8.0-139 base with the preserved local P2PDMA whitelist patch.
- AMDGPU reports a stock 44-bit DMA mask. The hardware run used Intel VT-d Translated mode; the full address-translation chain is not captured.
- Runtime: ROCK DKMS 6.16.13; ROCm 7.2.4; patched RCCL runtime based on 2.27.7 source.
- SGLang A/B: v0.5.18, TP=2, Qwen3.8-27B-AWQ; see the result table and caveats in [results](../../results/x99-r9700-qwen38.md).

## Evidence files

| File | Recorded evidence |
| --- | --- |
| `lspci.txt`, `topology.txt` | PCI IDs, device ancestry, BAR placement, root-port layout |
| `hip-ipc.txt` | Six recorded transfer/integrity cases over both GPU directions |
| `transferbench.txt` | Directional SDMA, GFX Push, and GFX Pull output |
| `rccl.txt` | Rank=2 AllReduce, direct-transport markers, bus-bandwidth sweep |
| `kernel-errors.txt` | Sanitized kernel-error sample for its recorded interval |
| `real_llm_tp2_stock_vs_p2p_ab_results.json` | Raw stock/direct inference A/B values and runtime logs |

Sanitized capture hashes and bounded test conditions are listed in [`results/evidence-manifest.json`](../../results/evidence-manifest.json). Source capture hashes in the file headers refer to the source artifact before repository sanitization; SHA-256 values in the manifest identify the checked-in sanitized artifacts.

These files are archived observations. They do not establish behavior on another board, kernel, RCCL build, workload, or IOMMU configuration.
