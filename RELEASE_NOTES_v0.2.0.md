# x99-amd-gpu-p2p v0.2.0 Release Notes (Draft)

Status: **draft for review**. This maintenance task does not create a Git tag or publish a GitHub Release.

## Highlights

- Updated the Linux P2PDMA record: the PCI maintainer reported the `8086:6f00` patch applied to `pci/p2pdma` for the v7.4 merge window. It was not yet in Linus' tree or a released kernel at the 2026-10-12 check.
- Preserved the Ubuntu 6.8 validated patch separately from the upstream submission artifact.
- Added a dated DMA44/high-BAR evidence review. It records the tested native 44-bit setup while leaving the untraced IOMMU/GPUVM/request-address chain open.
- Tightened diagnostics: topology must resolve to different Root Ports under the same matching host bridge; TransferBench needs valid measurements in both directions; HIP IPC requires explicit read/write verification; RCCL requires direct transport log markers; mocks require `TEST_MODE=YES` and cannot report production readiness.
- Added offline regression fixtures and a GitHub Actions workflow that does not run GPU tests.
- Added a hashed evidence manifest and expanded SGLang prefill/decode reporting.

## Recorded reference results

- TransferBench: SDMA and GFX Push are about 10.29 GB/s per direction; GFX Pull is about 3.14 GB/s in the recorded GPU0→GPU1 direction only.
- RCCL Rank-2 AllReduce: about 9.49 GB/s bus bandwidth for large messages. This is not a single-direction peer-copy metric.
- SGLang TP=2 prefill A/B medians: +32.1% at 1K, −3.7% at 4K, +0.5% at 16K, and +25.5% at 32K, with five runs per mode/tier and full observed ranges in [the result table](results/x99-r9700-qwen38.md).
- Decode comparisons are modest: +1.13% for the five-run single-request test; +1.0%, +0.8%, and +2.4% aggregate medians at C=1, C=2, and C=4 across three batches per mode.

These are archived observations from one Broadwell-EP / dual-R9700 test configuration. The A/B changes the RCCL build/configuration and transport together; it does not isolate P2P as the only cause of every end-to-end difference.

## Compatibility notes

The local RCCL override patch is tied to the RCCL 2.27.7 / `rocm-7.2.0` source baseline. Current `develop` retains the user-level override lookup before the Intel x86 clamp at the check date; no inspected formal release confirms the changed ordering. Older releases remain unaudited in this update. Verify the exact library before applying the patch.

The upstream kernel change is maintainer-applied but not yet merged/released at the check date. The original Ubuntu patch remains the validated local artifact.

## Validation

Run locally:

```bash
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh
bash tests/run-offline-tests.sh
python3 tests/validate_repository.py
```

The offline suite uses fixtures/mocks only. It does not compile or install a kernel, modify a production host, or run GPU benchmarks.
