# Case Study: SGLang Tensor Parallel Inference (Qwen3.8-27B-AWQ)

## Executive Summary

This case study evaluates the real-world inference impact of enabling PCIe P2PDMA and Direct P2P collective acceleration on a dual AMD Radeon AI PRO R9700 (gfx1201) system powered by an Intel Xeon E5-2697A v4 (Broadwell-EP, X99).

Using **Qwen3.8-27B-AWQ** under **SGLang v0.5.18** with Tensor Parallelism 2 (TP=2), inter-GPU AllReduce latency is the primary scaling bottleneck. Enabling Direct P2P delivers:
- **+243.8% AllReduce Collective Bandwidth** (2.76 GB/s -> 9.49 GB/s).
- **-15.5% TTFT Reduction** (342 ms -> 289 ms).
- **+42.5% Decode Throughput** (41.2 tok/s -> 58.7 tok/s at single concurrency).
- **+50.8% Aggregate Throughput** (78.4 tok/s -> 118.2 tok/s at concurrency 4).
- **Complete Elimination of Host RAM Bottlenecks**.

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
- **ROCm Version**: 7.2.0
- **AMDGPU Driver**: Stock `DMA_BIT_MASK(44)` (no custom GMC hack)
- **IOMMU**: Intel VT-d enabled in Translated mode
- **Inference Server**: SGLang v0.5.18 (commit `07eb3ec8`)
- **Attention Backend**: Triton (`--attention-backend triton`)
- **Decode Stack**: Mixed Triton/HIP
  - Full Attention: Triton
  - GDN / Recurrent Path: Triton (`torch_triton_sequential_recurrent`)
  - Tree-Verify: Triton (`tree_verify_attention_fwd / Patch065`)
  - AWQ Batched / Prefill (M > 1): Triton (`triton_awq_gemm`)
  - AWQ Single-Token Decode (M = 1): Native HIP GEMV (`awq_gemv_bf16_hip`)
- **AITER Status**: `AITER_ACTIVE = NO` (AITER is not installed or active in the validated SGLang v0.5.18 environment; this describes the validated software stack only and should not be interpreted as a hardware support limitation for AITER on gfx1201)
- **Triton Version**: 3.6.0 (ACTIVE)

---

## Benchmark Results

### 1. Inter-GPU Collective Bandwidth (`rccl-tests` AllReduce)

| Configuration | Bus Bandwidth | Latency (128 MB) | Bus Utilization |
| :--- | :--- | :--- | :--- |
| **Baseline (Stock Host Fallback)** | 2.76 GB/s | ~46.4 ms | ~23% of PCIe 3.0 x16 |
| **Direct P2P (`NCCL_P2P_LEVEL=PHB`)** | **9.49 GB/s** | **~13.5 ms** | **~79% of PCIe 3.0 x16** |
| **Relative Gain** | **+243.8% (3.44x)** | **-70.9%** | **Near theoretical line rate** |

---

### 2. SGLang Inference Metrics (Qwen3.8-27B-AWQ, TP2)

#### Single-Request Latency & Decode Speed (Prompt: 1024 tokens, Generation: 256 tokens)

| Metric | Stock Fallback | Direct P2P | Improvement |
| :--- | :--- | :--- | :--- |
| **TTFT (Time To First Token)** | 342.1 ms | **289.0 ms** | **-15.5% (faster)** |
| **Decode Throughput** | 41.2 tok/s | **58.7 tok/s** | **+42.5%** |
| **Time Per Output Token (TPOT)** | 24.27 ms | **17.03 ms** | **-29.8% (lower latency)** |
| **Total Generation Time** | 6.55 s | **4.65 s** | **-29.0%** |

#### Multi-Concurrency Throughput (Concurrency = 4)

| Metric | Stock Fallback | Direct P2P | Improvement |
| :--- | :--- | :--- | :--- |
| **Aggregate Decode Throughput** | 78.4 tok/s | **118.2 tok/s** | **+50.8%** |
| **P95 Latency** | 38.6 ms/tok | **23.1 ms/tok** | **-40.2%** |
| **Host CPU Utilization (AllReduce)** | High (memory copy threads) | Minimal (<5% CPU) | Host CPU decoupled |

---

## Analysis & Why Direct P2P Matters for RDNA4

1. **Tensor Parallel AllReduce Frequency**:
   In a 27B parameter model, each layer executes an AllReduce collective across GPUs during both the attention projection and MLP feed-forward phases. With 64+ transformer layers, an inference step triggers over 128 inter-GPU synchronizations per generated token.

2. **Latency Dominance**:
   When using host fallback (`PATH_SYS`), every AllReduce requires:
   - GPU 0 writes buffer to host pinned RAM over PCIe upstream.
   - Host CPU copies or coordinates buffer staging.
   - GPU 1 reads buffer from host RAM over PCIe downstream.
   - This triples the latency and saturates the CPU memory controller.

3. **Direct P2P Execution**:
   With `8086:6f00` whitelisted, GPU 0 directly writes into GPU 1's BAR aperture over the Root Complex internal switch interconnect. Host CPU RAM is completely bypassed, latency drops from ~46 ms to ~13 ms per large buffer, and decode throughput increases by +42.5% to +50.8%.

---

## Production Launch Configuration

To launch SGLang with Direct P2P enabled on dual R9700:

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
