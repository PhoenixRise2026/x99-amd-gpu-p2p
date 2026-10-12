# RCCL P2P Topology, Patch Scope, and Results

## Topology and transport are separate

RCCL assigns a topology distance such as `PATH_PHB` to GPU pairs and separately chooses a transport. The reference GPUs are under separate Root Ports of the same `8086:6f00` bridge. The archived direct run reports `isAllDirectP2p 1` and `via P2P/IPC`; the stock side of the SGLang A/B JSON reports `isAllDirectP2p 0` and `via SHM/direct/direct`.

`NCCL_P2P_LEVEL=PHB` requests P2P eligibility through a host bridge. It does not by itself prove that a particular RCCL build honors that setting or selected a direct transport; inspect the runtime logs.

## Compatibility patch and version status

The repository patch is a narrow compatibility change based on RCCL `rocm-7.2.0` / RCCL `2.27.7`, in `src/graph/paths.cc`. It moves the `ncclGetUserP2pLevel()` lookup after the Intel x86 default clamp so an explicit PHB level is not overwritten by the default.

Version review on **2026-10-12**:

- The official [ROCm/rocm-systems develop source](https://github.com/ROCm/rocm-systems/blob/develop/projects/rccl/src/graph/paths.cc) still calls `ncclGetUserP2pLevel()` **before** the Intel x86 clamp. The checked develop revision does not have equivalent ordering.
- The official [ROCm RCCL release notes](https://github.com/ROCm/rccl/releases) identify RCCL 2.27.7 with ROCm 7.2.0 and report no RCCL code change in ROCm 7.2.1–7.2.4. On that source-level evidence, the same ordering issue and patch applicability carry across the 7.2.x source line unless a downstream build changed it. No inspected formal release confirms the fix; verify each actual packaged library.
- RCCL releases older than the inspected 7.2 line were not re-audited for this maintenance update. Their status is **UNKNOWN**.
- The reference run used ROCm 7.2.4 with a patched RCCL library built from the 2.27.7 source baseline. That is a runtime observation for this build, not proof about every RCCL binary carrying the same version string.

The patch is therefore a version-scoped compatibility artifact. Inspect `paths.cc` and verify logs for the exact source/library build before deciding whether to apply it. Do not apply it mechanically to every current or future release.

## Bandwidth metrics

The archived Rank=2 Ring AllReduce result reaches 9.49 GB/s **bus bandwidth** for large messages. In [`rccl-tests` performance documentation](https://github.com/ROCm/rccl-tests/blob/develop_deprecated/doc/PERFORMANCE.md), algorithm bandwidth is based on collective payload divided by time; bus bandwidth scales it by the collective's estimated communication volume, commonly `2 * (nRanks - 1) / nRanks` for AllReduce. At two ranks that factor is 1, so the reported bus and algorithm bandwidth values can be numerically equal.

Neither value is a single-direction GPU peer-copy rate. TransferBench's approximately 10.29 GB/s per-direction SDMA/Push values are a different workload and metric.

## Archived RCCL sweep

Source: [`examples/broadwell-r9700/rccl.txt`](../examples/broadwell-r9700/rccl.txt). The file records direct transport markers and successful verification for each size.

| Message | Time | Bus bandwidth |
| ---: | ---: | ---: |
| 1 MiB | 0.237 ms | 4.418 GB/s |
| 4 MiB | 0.603 ms | 6.956 GB/s |
| 16 MiB | 1.900 ms | 8.832 GB/s |
| 64 MiB | 7.171 ms | 9.359 GB/s |
| 256 MiB | 28.286 ms | 9.490 GB/s |
| 512 MiB | 56.546 ms | 9.494 GB/s |
| 1024 MiB | 113.194 ms | 9.486 GB/s |

The log reports zero DMAR/AER errors during its sampled sweep. This is bounded to that capture and does not establish a general error-free guarantee.

## Run and inspect

```bash
export NCCL_P2P_LEVEL=PHB
export NCCL_DEBUG=INFO
./scripts/run-rccl.sh --full
```

Interpret a run as direct only when its output includes both `isAllDirectP2p 1` and `via P2P/IPC`. See [the evidence manifest](../results/evidence-manifest.json) and [version matrix](version-matrix.md).
