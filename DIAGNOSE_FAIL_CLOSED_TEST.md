# Diagnose Fail-Closed Regression Coverage

This file records the current automated offline test suite. It replaces the earlier manually reported cases, which predated the current topology and parser gates.

## Run

```bash
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh
bash tests/run-offline-tests.sh
python3 tests/validate_repository.py
```

The suite creates temporary fake sysfs trees and command fixtures. It does not access GPU hardware or run the external HIP IPC, TransferBench, or RCCL binaries. The full-diagnose success case injects all mocks under explicit `TEST_MODE=YES` and must end in `DIRECT_P2P_READY = TEST_ONLY`.

## Covered conditions

- Both PCI sysfs ancestries resolve to different Root Ports and the same `8086:6f00` host bridge.
- Same Root Port, different host-bridge domain, and insufficient GPU count fail closed.
- Unknown IOMMU mode remains INCONCLUSIVE.
- TransferBench matrix, CSV, and list formats: CPU-only, self-transfer, missing data, bytes mistaken for bandwidth, one-way-only, and valid bidirectional measurements.
- RCCL direct-marker pass, SHM fallback fail, and incomplete transport markers/exit-zero-without-transport-evidence inconclusive.
- HIP IPC missing-binary SKIP, all reported cases passing in both directions, failed case overriding zero exit, and exit-zero-without-integrity-evidence inconclusive.
- Passthrough IOMMU behavior stays INCONCLUSIVE because the address path is untraced; an unreadable DMA mask or empty kernel log also stays INCONCLUSIVE.
- Mocks without explicit `TEST_MODE=YES` are rejected; mocked full success remains TEST_ONLY.

## Recorded local result

On 2026-10-12, the shell suite completed with `OFFLINE_TESTS=PASS` and **45 assertions**; repository validation completed with `MANIFEST_VALIDATION=PASS`, `README_FACTS_AND_LINKS=PASS`, `LICENSE_AND_CI_SCOPE=PASS`, and `SECRET_SCAN=PASS`. Re-run these commands after any relevant change. A local pass validates fixtures and repository metadata only; it is not hardware, kernel, ROCm, or product acceptance.
