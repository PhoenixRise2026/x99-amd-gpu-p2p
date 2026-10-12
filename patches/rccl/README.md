# RCCL PHB Override Compatibility Patch

This patch is a version-scoped compatibility artifact for the RCCL source baseline associated with ROCm 7.2.0 / RCCL 2.27.7.

## Source behavior and scope

In that source baseline, the Intel x86 platform default can set `p2pLevel = PATH_PXB` after the user-level value was read. Moving `ncclGetUserP2pLevel(&p2pLevel)` below that default allows an explicit `NCCL_P2P_LEVEL=PHB` setting to be honored for the reference Root-Port-to-Root-Port topology.

The reference ROCm 7.2.4 runtime used a library built from the 2.27.7 source baseline with this patch. Upstream [PR #12714](https://github.com/ROCm/rocm-systems/pull/12714) merged to `ROCm/rocm-systems` `develop` on 2026-10-11 as [commit `65575fbbe6f73b9d9d96bfbcb523c856709e664c`](https://github.com/ROCm/rocm-systems/commit/65575fbbe6f73b9d9d96bfbcb523c856709e664c). The current [develop source](https://github.com/ROCm/rocm-systems/blob/develop/projects/rccl/src/graph/paths.cc) now applies the CPU default before reading `NCCL_P2P_DISABLE` / `NCCL_P2P_LEVEL`, matching the ordering intent of this patch. Do not apply this historical patch to a source tree that already contains the upstream change.

That merge confirms `develop` only; it does not assign a formal RCCL version or prove inclusion in a ROCm package. The official 7.2.1–7.2.4 release notes report no RCCL source changes after 7.2.0, so this later merge must not be attributed to those releases without source/package evidence. Older releases were not re-audited. See [the maintained compatibility analysis](../../docs/rccl.md).

Inspect the exact `src/graph/paths.cc` and library before applying this patch to another build. Do not treat its presence here as a requirement for every newer RCCL version.

## Runtime verification

`NCCL_P2P_LEVEL=PHB` is a request, not proof of the selected transport. A direct result must include both `isAllDirectP2p 1` and `via P2P/IPC` in RCCL logs. The reference archived AllReduce run reports about 9.49 GB/s Rank-2 bus bandwidth; this is not a one-way peer-copy rate.

## Provenance and licensing

- Base repository: [ROCm/rccl](https://github.com/ROCm/rccl)
- Base tag: `rocm-7.2.0` (RCCL 2.27.7)
- Base commit: `0d2c4fd4c5ea8aa96b4ac4eb468fb4146ab2c921`
- Target: `src/graph/paths.cc`
- Patch: `0001-graph-honor-explicit-p2p-level-after-platform-limit.patch`

The diff is derived from upstream RCCL source and follows its BSD-3-Clause licensing and attribution requirements; see the repository's [license notes](../../LICENSES/README.md).
