# Case Study: SGLang Tensor Parallel Inference (Qwen3.8-27B-AWQ)

## Executive Summary

This case study documents real-world LLM tensor-parallel inference (TP=2) running on dual AMD Radeon AI PRO R9700 GPUs across Intel Broadwell-EP Root Ports using **SGLang v0.5.18**.

All benchmark data in this case study is strictly locked to the verified empirical trial results recorded in `results/x99-r9700-qwen38.md` and raw execution trace `real_llm_tp2_stock_vs_p2p_ab_results.json`.

---

## Hardware & Software Stack

### Hardware Configuration
- **Platform**: Intel X99, Single-socket Intel Xeon E5-2697A v4 (16C/32T, 2.60 GHz)
- **Host Bridge**: Intel Broadwell-EP Host Bridge (`8086:6f00`)
- **System Memory**: 128 GB DDR4-2400 ECC Registered
- **GPUs**: 2x AMD Radeon AI PRO R9700 (RDNA4 gfx1201, 32 GB VRAM each)
- **PCIe Topology**:
  - GPU 0 (`05:00.0`): PCIe 3.0 x16 under Root Port `0000:00:02.0`
  - GPU 1 (`08:00.0`): PCIe 3.0 x16 under Root Port `0000:00:03.0`

### Software & Inference Runtime
- **Linux Kernel**: 6.8.0-139 patched with Broadwell `8086:6f00` P2PDMA whitelist
- **ROCm Version**: 7.2.4
- **AMDGPU Driver**: Stock `DMA_BIT_MASK(44)` (no custom GMC hack)
- **IOMMU**: Intel VT-d enabled in Translated mode (`DMA-FQ`)
- **Model**: `Qwen/Qwen3.8-27B-AWQ-MTP` (Dense DeltaNet + Attention hybrid architecture, 64 layers)
- **Serving Framework**: SGLang v0.5.18 (commit `07eb3ec8`)
- **Attention Backend**: Triton (`--attention-backend triton`)
- **Decode Stack**: Mixed Triton/HIP
  - Full Attention: Triton
  - GDN / Recurrent Path: Triton (`torch_triton_sequential_recurrent`)
  - Tree-Verify: Triton (`tree_verify_attention_fwd / Patch065`)
  - AWQ Batched / Prefill ($M > 1$): Triton (`triton_awq_gemm`)
  - AWQ Single-Token Decode ($M = 1$): Native HIP GEMV (`awq_gemv_bf16_hip`)
- **AITER Status**: `AITER_ACTIVE = NO` (AITER is not installed or active in the validated SGLang v0.5.18 environment; this describes the validated software stack only and should not be interpreted as a hardware support limitation for AITER on gfx1201)
- **Triton Version**: 3.6.0 (ACTIVE)

---

## Verified Benchmark Results

### Test 1: Single Request Decode (Prompt: 369 tokens, Generation: 256 tokens)

| Metric | Stock (via SHM Staging) | Direct P2P (PCIe Host Bridge Direct) | Delta |
| :--- | :---: | :---: | :---: |
| **Decode Throughput** | 30.93 tok/s | **31.28 tok/s** | +1.13% |
| **Time Per Output Token (TPOT)** | 32.33 ms | **31.97 ms** | -0.36 ms |
| **Time to First Token (TTFT)** | 262.70 ms | **261.45 ms** | -1.25 ms |
| **End-to-End Latency** | 16.78 s | **16.60 s** | -0.18 s |

---

### Test 4: Concurrency Scaling Throughput (Prompt: 369 tokens, Generation: 256 tokens per req)

| Concurrency Level | Stock (tok/s) | Direct P2P (tok/s) | P2P TPOT |
| :---: | :---: | :---: | :---: |
| **C = 1** | 31.01 | **31.31** | 32.07 ms |
| **C = 2** | 37.61 | **37.90** | 52.41 ms |
| **C = 4** | 69.41 | **71.10** | 54.43 ms |

---

## Analysis: Why P2P Matters for TP2 Inference

1. **Transport Mechanism Verification**:
   - Under stock RCCL, `isAllDirectP2p = 0` forced all TP=2 AllReduce collective tensors through host memory bounce buffers (`via SHM/direct/direct`).
   - Under patched RCCL with `NCCL_P2P_LEVEL=PHB`, `isAllDirectP2p = 1` routed AllReduce directly across Root Ports through the host bridge (`via P2P/IPC`), cutting individual collective barrier latency from ~0.9 ms to ~0.24 ms per invocation.

2. **Compute-Bound vs Communication-Bound Behavior**:
   - Single-request autoregressive decode is predominantly memory-bandwidth bound within each GPU (reading model weights from VRAM), so inter-GPU AllReduce accounts for a modest fraction of total token latency.
   - At higher concurrency (C=4), communication overlap and reduced host memory traffic yield measurable throughput gains (69.41 -> 71.10 tok/s).
   - Most importantly, the direct P2P transport completely decouples inter-GPU traffic from host DRAM and the CPU memory controller, maintaining 100% bus stability with zero kernel errors.

---

## Production Launch Configuration

To launch SGLang with Direct P2P enabled on dual AMD R9700 GPUs:

```bash
#!/bin/bash
# SGLang TP2 Production Launch Script for Dual AMD R9700 on Broadwell-EP

export HIP_VISIBLE_DEVICES=0,1
export NCCL_P2P_LEVEL=PHB
export NCCL_BUFFSIZE=8388608

python3 -m sglang.launch_server \
  --model-path /models/Qwen3.8-27B-AWQ \
  --tp 2 \
  --attention-backend triton \
  --host 0.0.0.0 \
  --port 8000 \
  --mem-fraction-static 0.88 \
  --context-length 32768
```
