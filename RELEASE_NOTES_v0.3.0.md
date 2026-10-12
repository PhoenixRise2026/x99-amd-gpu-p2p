# v0.3.0 — Dual R9700 TP2 Inference Research

## Research scope

- Add a separate SGLang FP8 TP2 inference research layer while preserving the v0.2.0 P2P communication evidence and conclusions.
- Record P5B-R Plain / MTP / DFlash2 decode-rate scalars at 8K, 32K, and 64K as `SUMMARY_ONLY`. These are stored summary observations, not independently reproducible per-run benchmark statistics.
- Preserve the 32K DFlash2 discrepancy: stored 55.39 tok/s; formula recalculation 55.395043 tok/s; conventional two-decimal half-up result 55.40 tok/s; source rounding rule unknown.
- Document one 224000-input-token TP2 request with HTTP 200, `finish_reason=stop`, and `semantic_pass=true`. Actual generated-token count is missing; this single request does not establish long-run stability or a general 256K capability.
- Document the 229000-input-token request as `PARTIAL_OR_ABORTED`, with `finish_reason=abort`, `semantic_pass=false`, and a 227701-token rejection boundary observed for this software stack and configuration. HTTP 200 is not inference success.
- State that 128K and 192K results are not included in this Option B audited evidence set; this does not assess other historical experiments that have not been reviewed. The reviewed evidence does not establish successful 256K inference.

## Evidence and attribution limits

P5B-R per-run samples, repetitions, aggregation method, exact model/weight provenance, package versions, launch configuration, build identity, and run-linked memory telemetry are not established by the available P5B summary. No median, variance, confidence interval, or reproducible benchmark claim is made.

MTP and DFlash2 are inference-stack optimizations. Their gains are not attributed to PCIe P2P. These inference observations do not change the v0.2.0 evidence manifest or historical P2P measurements.
