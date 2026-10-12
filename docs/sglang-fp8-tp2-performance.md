# SGLang FP8 TP2 Decode-Rate Observations — Evidence-Bounded Results

The P5B-R source summary is classified as `SUMMARY_ONLY`; it is not a reproducible, per-run benchmark report.

## Purpose and scope

P5B-R records stored decode-rate scalars for Plain, MTP, and DFlash2 at 8K, 32K, and 64K input contexts. This report records those nine values, independently checks the arithmetic available in the summary, and keeps the rounding discrepancy visible. It does not alter the v0.2.0 P2P communication results.

The study context describes SGLang FP8 TP2 inference on an X99 dual-R9700 system. The P5B-R result JSON itself does not bind each row to a verified machine, model weights, runtime build, or run configuration. Treat that platform description as context, not per-run provenance.

## Evidence and known configuration

| Item | Audit status |
| --- | --- |
| Evidence class | `SUMMARY_ONLY` |
| Stored conditions | Plain / MTP / DFlash2 × 8K / 32K / 64K; nine scalar rows |
| Input tokens | 8,000 / 32,000 / 64,000 as stored |
| Completion tokens | 256 reported for each row |
| Decode formula checked | `(completion_tokens - 1) / decode_time_seconds` |
| Repeated runs / sample count | `NOT_RECORDED`; per-run samples `NOT_LOCATED` in the bounded inventory |
| Statistic used for the stored rates | `UNKNOWN`; no median, standard deviation, or confidence interval is established |
| Model and weight identifier / checksum | `NOT_VERIFIED` from the P5B-R source |
| SGLang, ROCm, RCCL, AITER versions and build/patch ID | `NOT_VERIFIED` from the P5B-R source |
| TP, FP8 KV, MTP, DFlash2 launch configuration per row | `NOT_VERIFIED` from the P5B-R source |
| Concurrency, cache state, warm-up, compile state, explicit PASS state | `NOT_RECORDED` |
| Run-linked VRAM/GTT and device identity | `NOT_VERIFIED`; source aliases lack run/BDF linkage |

## Stored and recalculated decode rates

The stored values below are source-summary values. The recalculated column uses the formula above and the source-stored decode time; it is an arithmetic check, not an independent replay of the benchmark.

| Context | Mode | Stored decode (tok/s) | Formula recalculation (tok/s) |
| --- | --- | ---: | ---: |
| 8K | Plain | 21.48 | 21.480196 |
| 8K | MTP | 42.29 | 42.287856 |
| 8K | DFlash2 | 51.44 | 51.437216 |
| 32K | Plain | 19.21 | 19.214250 |
| 32K | MTP | 45.32 | 45.315610 |
| 32K | DFlash2 | 55.39 | 55.395043 |
| 64K | Plain | 16.82 | 16.823577 |
| 64K | MTP | 28.60 | 28.604440 |
| 64K | DFlash2 | 59.81 | 59.807210 |

Eight of nine formula values round to the stored value using conventional half-up rounding to two decimals. For 32K DFlash2, the stored value is **55.39 tok/s**, the formula result is **55.395043 tok/s**, and conventional half-up rounding gives **55.40 tok/s**. The source does not say whether it truncated, used a more precise timer, or aggregated another value. Keep the discrepancy as `ROUNDING_METHOD_UNVERIFIED`; do not silently replace the stored figure.

## Ratios from stored summary values

These are ratios of stored scalar values only. They are not repeated-run speedups, uncertainty estimates, or causal measurements.

| Context | MTP / Plain | DFlash2 / Plain |
| --- | ---: | ---: |
| 8K | 1.968808× | 2.394786× |
| 32K | 2.359188× | 2.883394× |
| 64K | 1.700357× | 3.555886× |

## What is and is not established

**Independently checkable:** the source file contains nine stored mode/context scalars and reports 256 completion tokens per row; dividing 255 by each stored decode time reproduces the formula column above. The ratios can be recalculated from the stored rates. The 32K DFlash2 rounding mismatch is explicit.

**Not independently reproducible:** the source contains no per-run samples, repetition count, aggregation rule, complete launch configuration, per-row PASS/FAIL status, exact P5B model/weight provenance, package versions, build or patch identity, or run-linked memory telemetry. The arithmetic check does not supply those missing inputs.

MTP and DFlash2 are inference-software modes. Their differences cannot be attributed to PCIe P2P; P5B-R causality remains **not established**. A P2P claim would require a separate controlled SHM/P2P comparison holding the relevant software, model, request, cache, compilation, and runtime variables fixed.

## Reproduction limits and next evidence

This summary supports only a narrowly labeled historical observation. It cannot support a claim of independently reproducible benchmark statistics. To make a repeatable comparison, future evidence would need per-run input/output/decode timing records, a declared aggregation rule, exact model and weight hashes, complete startup/configuration records, package/build provenance, cache and warm-up policy, concurrency, failure handling, and run-linked device memory records.

The source and derivative hashes are kept as separate fields in the accompanying evidence manifest; source files are not part of this report.
