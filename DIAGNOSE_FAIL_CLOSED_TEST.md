# Diagnose Fail-Closed Unit Test Matrix

This document records the verification of the fail-closed behavior of `scripts/diagnose.sh` across all test conditions (Cases A through F).

## Test Matrix & Results

| Case | Scenario | Command / Injected Condition | Expected Prerequisites | Expected P2P Ready | Actual Result | Status |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: |
| **Case A** | Default run (no args) | `./scripts/diagnose.sh` | `PASS` | `INCONCLUSIVE` | `P2P_PREREQUISITES = PASS`<br>`DIRECT_P2P_READY = INCONCLUSIVE` | **PASS** |
| **Case B** | Missing GPU (1 GPU detected) | `TEST_MOCK_GPU_COUNT=1 ./scripts/diagnose.sh` | `FAIL` | `NO` | `P2P_PREREQUISITES = FAIL`<br>`DIRECT_P2P_READY = NO` | **PASS** |
| **Case C** | IOMMU mode unknown | `TEST_MOCK_IOMMU=UNKNOWN ./scripts/diagnose.sh` | `FAIL` | `NO` | `P2P_PREREQUISITES = FAIL`<br>`DIRECT_P2P_READY = NO` | **PASS** |
| **Case D** | TransferBench active failure | `TEST_MOCK_TRANSFERBENCH=FAIL ./scripts/diagnose.sh --full` | `PASS` | `NO` | `P2P_PREREQUISITES = PASS`<br>`DIRECT_P2P_READY = NO` | **PASS** |
| **Case E** | RCCL fallback to SHM staging | `TEST_MOCK_RCCL=FAIL ./scripts/diagnose.sh --full` | `PASS` | `NO` | `P2P_PREREQUISITES = PASS`<br>`DIRECT_P2P_READY = NO` | **PASS** |
| **Case F** | All test mocks PASS | `TEST_MOCK_HIP_IPC=PASS TEST_MOCK_TRANSFERBENCH=PASS TEST_MOCK_RCCL=PASS ./scripts/diagnose.sh --full` | `PASS` | `TEST_ONLY` (`TEST_MODE=YES`) | `P2P_PREREQUISITES = PASS`<br>`DIRECT_P2P_READY = TEST_ONLY`<br>`TEST_MODE = YES` | **PASS** |

## Raw Test Execution Log

```text
=== Case A: Default run ===
P2P_PREREQUISITES = PASS
DIRECT_P2P_READY = INCONCLUSIVE

=== Case B: Missing GPU ===
P2P_PREREQUISITES = FAIL
DIRECT_P2P_READY = NO

=== Case C: IOMMU unknown ===
P2P_PREREQUISITES = FAIL
DIRECT_P2P_READY = NO

=== Case D: TransferBench mock FAIL ===
P2P_PREREQUISITES = PASS
DIRECT_P2P_READY = NO

=== Case E: RCCL fallback to SHM ===
P2P_PREREQUISITES = PASS
DIRECT_P2P_READY = NO

=== Case F: All mocks PASS ===
P2P_PREREQUISITES = PASS
DIRECT_P2P_READY = TEST_ONLY
TEST_MODE = YES
```

## Fail-Closed Guarantees Confirmed
1. Missing explicit active tests in default mode does not emit `DIRECT_P2P_READY = YES`.
2. Unconfirmed or missing IOMMU translation does not assume Translated mode.
3. Test mocks cannot bypass production gates to emit `DIRECT_P2P_READY = YES`.

---

## TransferBench Real Output Parser Fixtures (Cases TB-A to TB-F)

| Case | Scenario | Injected TransferBench Output | Expected TB Result | Actual Result | Status |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **TB-A** | Standard matrix with GPU0/GPU1 off-diagonal | Header has GPU 00/01; `GPU 00 -> N/A 10.29`, `GPU 01 -> 10.27 N/A` | `PASS` | `PASS` | **PASS** |
| **TB-B** | CPU->GPU only (no GPU peer transfers) | `CPU 00 -> 4.50 4.50` | `INCONCLUSIVE` | `INCONCLUSIVE` | **PASS** |
| **TB-C** | GPU self-transfer only (GPU 00 -> GPU 00) | `GPU 00 -> 20.00 N/A` | `INCONCLUSIVE` | `INCONCLUSIVE` | **PASS** |
| **TB-D** | Matrix all N/A | `GPU 00 -> N/A N/A`, `GPU 01 -> N/A N/A` | `FAIL` | `FAIL` | **PASS** |
| **TB-E** | Header contains GB/s, cells are bare numbers | `GPU 00 -> ... 10.29`, `GPU 01 -> 10.27 ...` | `PASS` | `PASS` | **PASS** |
| **TB-F** | Reference multi-line list log | `examples/broadwell-r9700/transferbench.txt` | `PASS` | `PASS` | **PASS** |

### Parser Guarantees Confirmed
1. `TRANSFERBENCH_REAL_OUTPUT_PARSER = PASS`
2. `TRANSFERBENCH_CPU_FALSE_POSITIVE_FIXED = YES`: CPU-only transfers cannot evaluate to PASS.
3. `TRANSFERBENCH_MATRIX_FALSE_NEGATIVE_FIXED = YES`: Cells without verbatim `GB/s` correctly resolve off-diagonal peer bandwidth.
