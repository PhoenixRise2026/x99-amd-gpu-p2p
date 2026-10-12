# Case Study: SGLang Tensor Parallel Inference (Qwen3.8-27B-AWQ)

This case study links the preserved TP=2 A/B dataset for stock-RCCL/SHM and patched-RCCL/direct-P2P modes on one Broadwell-EP host with two Radeon AI PRO R9700 GPUs. It describes a specific run, not a general performance guarantee.

## Recorded stack

- Intel Xeon E5-2697A v4, host bridge `8086:6f00`, two R9700 GPUs under Root Ports `0000:00:02.0` and `0000:00:03.0`.
- Ubuntu 24.04 / patched Ubuntu 6.8.0-139 kernel; AMDGPU stock 44-bit DMA mask.
- Intel VT-d Translated mode was the recorded test configuration. The exact DMA-BUF/IOMMU/GPUVM/request-address chain remains untraced; see [high-address investigation](high-address-p2p-investigation.md).
- ROCm 7.2.4; RCCL 2.27.7 source baseline with the local PHB override patch in the direct-P2P condition.
- SGLang v0.5.18, TP=2, Qwen3.8-27B-AWQ, Triton attention backend. AITER was absent from this tested stack.

## Results and limitations

The stock JSON logs show `isAllDirectP2p 0` and `via SHM/direct/direct`; the patched condition shows `isAllDirectP2p 1` and `via P2P/IPC`. The full 1K/4K/16K/32K prefill ranges, single-request decode, and three concurrency tiers are reported in [the benchmark results](../results/x99-r9700-qwen38.md).

Prefill measurements are mixed: 1K and 32K medians are higher in the patched/direct condition, 4K is lower, and 16K is nearly unchanged. Decode medians are modestly higher in the direct condition. The comparison changes the RCCL library/configuration and selected transport; it does not isolate transport as the only causal variable. No generic performance claim is made.

The lower-level TransferBench, RCCL, and HIP IPC captures are separate measurements and should not be conflated with SGLang's end-to-end throughput. Newer inference optimizations such as FP8, MTP, or DFlash2 require their own controlled A/B before any P2P attribution.
