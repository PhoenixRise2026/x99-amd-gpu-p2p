# RCCL P2P Topology, Patch Scope, and Results

## Topology and transport are separate

RCCL assigns a topology distance such as `PATH_PHB` to GPU pairs and separately chooses a transport. The reference GPUs are under separate Root Ports of the same `8086:6f00` bridge. The archived direct run reports `isAllDirectP2p 1` and `via P2P/IPC`; the stock side of the SGLang A/B JSON reports `isAllDirectP2p 0` and `via SHM/direct/direct`.

`NCCL_P2P_LEVEL=PHB` requests P2P eligibility through a host bridge. It does not by itself prove that a particular RCCL build honors that setting or selected a direct transport; inspect the runtime logs.

## Compatibility patch and version status

The repository patch is a narrow compatibility change based on RCCL `rocm-7.2.0` / RCCL `2.27.7`, in `src/graph/paths.cc`. It moves the `ncclGetUserP2pLevel()` lookup after the Intel x86 default clamp so an explicit PHB level is not overwritten by the default.

Version review on **2026-10-12**:

- [ROCm/rocm-systems PR #12714](https://github.com/ROCm/rocm-systems/pull/12714) was merged into `develop` on 2026-10-11 as [commit `65575fbbe6f73b9d9d96bfbcb523c856709e664c`](https://github.com/ROCm/rocm-systems/commit/65575fbbe6f73b9d9d96bfbcb523c856709e664c). The [current `develop` source](https://github.com/ROCm/rocm-systems/blob/develop/projects/rccl/src/graph/paths.cc) applies the Intel/ARM/Zhaoxin CPU defaults first and calls `ncclGetUserP2pLevel()` afterward. The [branch comparison](https://github.com/ROCm/rocm-systems/compare/65575fbbe6f73b9d9d96bfbcb523c856709e664c...develop) confirms that `develop` descends from this commit.
- This verifies the behavior on `develop`; it does **not** identify a formal RCCL version or ROCm package containing the change. The PR also adds a development changelog entry, but a `develop` merge alone is not a release. Check the exact tag/package source before making a release-version claim.
- The local patch remains a historical compatibility artifact for the RCCL `rocm-7.2.0` / 2.27.7 source baseline. That source baseline reads the environment override before the platform default, so the patch remains relevant to that source unless downstream changes differ. Do not apply it to a source tree that already contains commit `65575fb`.
- The official [ROCm RCCL release notes](https://github.com/ROCm/rccl/releases) identify RCCL 2.27.7 with ROCm 7.2.0 and report no RCCL source changes in ROCm 7.2.1–7.2.4. These records do not establish that those packages contain the later `develop` change; inspect the exact packaged source/library. Older releases remain **UNKNOWN**.
- The reference run used ROCm 7.2.4 with a patched RCCL library built from the 2.27.7 source baseline. This is an observation for that build, not proof about every RCCL binary carrying the same version string.

The patch is version-scoped and has not been removed or rewritten. Inspect `paths.cc` and verify logs for the exact source/library build before deciding whether to apply it.

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
