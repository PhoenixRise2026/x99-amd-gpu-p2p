# SGLang TP2 Long-Context Boundaries — Evidence-Bounded Results

These are request-level observations from the reviewed P0 evidence, not a general context-capacity certification.

## Purpose and runtime identity

The P7 records distinguish request submission, server acceptance, execution completion, and a harness semantic flag. The reviewed runtime evidence identifies a two-way tensor-parallel run and the recorded model label `Qwen3.8-27B-FP8`, FP8 e4m3 KV cache, Triton attention, and DFLASH speculative mode. The exact SGLang/ROCm/RCCL package versions and model-weight checksum are `UNKNOWN`. A runtime image identifier was recorded in source evidence but is omitted as an environment identifier. Device identifiers and private paths are omitted.

## Reviewed request cases

| Requested input | Evidence status | HTTP | Server accepted full input | Finish reason | Harness semantic flag | Interpretation |
| ---: | --- | ---: | --- | --- | --- | --- |
| 224,000 | `VALIDATED_SUCCESS` for one request; TP2 identity present | 200 | Yes, 224,000 tokens | `stop` | `semantic_pass=true` | One execution-success case with a passing fixed harness check |
| 229,000 | Boundary request; TP2 identity present | 200 | No | `abort` | `semantic_pass=false` | `PARTIAL_OR_ABORTED`; context-limit rejection |

### 224K single case

The manifest and result record 224000 requested input tokens; the result reports 224000 server prompt tokens, HTTP 200, `finish_reason=stop`, and `semantic_pass=true`. The request was attempted once. TTFT was 330.757 seconds and end-to-end time was 330.872 seconds. The output budget was 128 tokens, but actual generated-token usage is missing. Therefore no output decode rate or complete output throughput can be derived.

The semantic flag represents a fixed short harness sentinel check. It is not a general semantic-quality evaluation. One successful request does not establish repeatability, sustained stability, or a general service-level guarantee.

### 229K boundary case

The request asked for 229000 input tokens. The reviewed P0 server log records rejection above an effective 227701-token admission limit for this stack and configuration. The result reports HTTP 200, `finish_reason=abort`, `semantic_pass=false`, and abort-time usage counters of one prompt and one completion token. It did not complete inference over the requested full input. HTTP 200 describes the HTTP exchange; it does not establish server acceptance, completed inference, or semantic success.

The runtime's configured context cap of 262144 is configuration metadata. It does not override the observed rejection and does not demonstrate a completed 256K request. The observed 227701-token limit is specific to this software stack and configuration, not a hardware-theoretical limit.

## Context-tier status

| Tier / case | Status |
| --- | --- |
| 128K | Not included in this Option B audited evidence set; other historical experiments were not assessed |
| 192K | Not included in this Option B audited evidence set; other historical experiments were not assessed |
| 224K | One successful request with `semantic_pass=true`; actual generated-token count missing |
| 229K | `PARTIAL_OR_ABORTED`; rejected above the observed 227701-token limit |
| 256K | No successful 256K inference is established by the evidence reviewed here; the configured cap is not a completed request |

Do not combine these tiers into a claim that “256K is validated.” The 224K case is one request; 229K is a failed boundary case. Neither establishes a continuous accepted range or a general maximum. The 128K/192K scope statement does not assess separate historical experiments outside the reviewed evidence set.

## Reproducibility limits and next evidence

The exact model-weight hash and software package versions remain unknown. The 224K result lacks actual generated-token count. This evidence does not establish repeated long-context reliability, broad semantic correctness, or measured output throughput. The raw activity monitor was not retrieved; detailed time-series GPU-memory claims are omitted. The Option B review did not include 128K or 192K artifacts; this report makes no finding about other historical experiments.

Future research should capture exact software and model-weight provenance, output token usage, repeated requests, request-level acceptance and completion fields, and a documented semantic evaluation. Context tiers must be tested and reported independently. This report makes no claim about a 260000-token request.
