#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
PASS_COUNT=0

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_equal() {
    local expected="$1" actual="$2" name="$3"
    [[ "$actual" == "$expected" ]] || fail "$name: expected '$expected', got '$actual'"
    PASS_COUNT=$((PASS_COUNT + 1))
}

assert_contains() {
    local haystack="$1" needle="$2" name="$3"
    [[ "$haystack" == *"$needle"* ]] || fail "$name: missing '$needle'"
    PASS_COUNT=$((PASS_COUNT + 1))
}

assert_not_contains() {
    local haystack="$1" needle="$2" name="$3"
    [[ "$haystack" != *"$needle"* ]] || fail "$name: unexpected '$needle'"
    PASS_COUNT=$((PASS_COUNT + 1))
}

run_tb_case() {
    local name="$1" expected="$2" input="$3" actual
    actual="$(printf '%s\n' "$input" | awk -f "$REPO_ROOT/scripts/lib/transferbench-parser.awk")"
    assert_equal "$expected" "$actual" "$name"
}

run_tb_case "CPU-only matrix" INCONCLUSIVE $'SRC+EXE\\DST   GPU 00   GPU 01\nCPU 00 -> 4.50 4.50'
run_tb_case "GPU self-transfer" INCONCLUSIVE $'SRC+EXE\\DST   GPU 00   GPU 01\nGPU 00 -> 20.00 N/A'
run_tb_case "one peer direction" INCONCLUSIVE $'SRC+EXE\\DST   GPU 00   GPU 01\nGPU 00 -> N/A 10.29\nGPU 01 -> N/A N/A'
run_tb_case "both peer directions" PASS $'SRC+EXE\\DST   GPU 00   GPU 01\nGPU 00 -> N/A 10.29\nGPU 01 -> 10.27 N/A'
run_tb_case "CSV bytes are not bandwidth" FAIL $'source,destination,executor,bytes,seconds,bandwidth_GBps\nGPU0,GPU1,GPU0,67108864,0.0065,0\nGPU1,GPU0,GPU1,67108864,0.0065,0'
run_tb_case "CSV requires both directions" INCONCLUSIVE $'source,destination,executor,bytes,seconds,bandwidth_GBps\nGPU0,GPU1,GPU0,67108864,0.0065,10.29'
run_tb_case "valid header-labeled CSV both directions" PASS $'source,destination,executor,bytes,seconds,bandwidth_GBps\nGPU0,GPU1,GPU0,67108864,0.0065,10.29\nGPU1,GPU0,GPU1,67108864,0.0065,10.27'
run_tb_case "unlabeled CSV is inconclusive" INCONCLUSIVE $'GPU0,GPU1,GPU0,67108864,0.0065,10.29\nGPU1,GPU0,GPU1,67108864,0.0065,10.27'
run_tb_case "directional list output" PASS $'Case: dma_0_to_1 (Direction: GPU 0 -> GPU 1)\n  Size: 64 MiB Avg: 10.29 GB/s\nCase: dma_1_to_0 (Direction: GPU 1 -> GPU 0)\n  Size: 64 MiB Avg: 10.27 GB/s'
run_tb_case "sanitized reference log" PASS "$(cat "$REPO_ROOT/examples/broadwell-r9700/transferbench.txt")"

source "$REPO_ROOT/scripts/lib/diagnose-common.sh"
assert_equal PASS "$(classify_rccl_output $'NCCL INFO Check P2P Type isAllDirectP2p 1 directMode 1\nNCCL INFO Channel 00 via P2P/IPC comm 0x...')" "RCCL P2P log evidence"
assert_equal FAIL "$(classify_rccl_output $'NCCL INFO isAllDirectP2p 0\nNCCL INFO Channel 00 via SHM/direct/direct')" "RCCL SHM fallback"
assert_equal INCONCLUSIVE "$(classify_rccl_output 'NCCL INFO isAllDirectP2p 1')" "RCCL direct flag without transport evidence"
assert_equal INCONCLUSIVE "$(classify_rccl_output 'benchmark completed successfully')" "RCCL exit alone is insufficient"

NO_EVIDENCE_BIN="$TMP_ROOT/hip-ipc-no-evidence"
cat > "$NO_EVIDENCE_BIN" <<'EOF'
#!/usr/bin/env bash
echo "HIP IPC completed"
EOF
chmod +x "$NO_EVIDENCE_BIN"
set +e
NO_EVIDENCE_OUT="$("$REPO_ROOT/scripts/check-hip-ipc.sh" --binary "$NO_EVIDENCE_BIN" 2>&1)"
NO_EVIDENCE_STATUS=$?
set -e
assert_equal 3 "$NO_EVIDENCE_STATUS" "HIP IPC zero exit without integrity evidence"
assert_contains "$NO_EVIDENCE_OUT" INCONCLUSIVE "HIP IPC zero exit is not a pass"

MISSING_IPC="$TMP_ROOT/does-not-exist"
set +e
MISSING_OUT="$("$REPO_ROOT/scripts/check-hip-ipc.sh" --binary "$MISSING_IPC" 2>&1)"
MISSING_STATUS=$?
set -e
assert_equal 2 "$MISSING_STATUS" "missing HIP IPC binary"
assert_contains "$MISSING_OUT" SKIP "missing HIP IPC binary is a skip"

VERIFIED_IPC_BIN="$TMP_ROOT/hip-ipc-verified"
cat > "$VERIFIED_IPC_BIN" <<'EOF'
#!/usr/bin/env bash
cat <<'LOG'
DIRECTION: GPU 0 (Exporter) -> GPU 1 (Importer)
[Test 1] 1 MiB
Forward Read Verify: PASS
Reverse Write Verify: PASS
DIRECTION: GPU 1 (Exporter) -> GPU 0 (Importer)
[Test 2] 1 MiB
Forward Read Verify: PASS
Reverse Write Verify: PASS
LOG
EOF
chmod +x "$VERIFIED_IPC_BIN"
assert_equal 0 "$("$REPO_ROOT/scripts/check-hip-ipc.sh" --binary "$VERIFIED_IPC_BIN" >/dev/null 2>&1; echo $?)" "HIP IPC explicit bidirectional evidence"

FAILED_IPC_BIN="$TMP_ROOT/hip-ipc-failed-case"
cat > "$FAILED_IPC_BIN" <<'EOF'
#!/usr/bin/env bash
cat <<'LOG'
DIRECTION: GPU 0 (Exporter) -> GPU 1 (Importer)
[Test 1] 1 MiB
Forward Read Verify: PASS
Reverse Write Verify: PASS
[Test 2] 16 MiB
Forward Read Verify: FAIL
Reverse Write Verify: PASS
DIRECTION: GPU 1 (Exporter) -> GPU 0 (Importer)
[Test 3] 1 MiB
Forward Read Verify: PASS
Reverse Write Verify: PASS
LOG
EOF
chmod +x "$FAILED_IPC_BIN"
set +e
FAILED_IPC_OUT="$("$REPO_ROOT/scripts/check-hip-ipc.sh" --binary "$FAILED_IPC_BIN" 2>&1)"
FAILED_IPC_STATUS=$?
set -e
assert_equal 1 "$FAILED_IPC_STATUS" "HIP IPC failed case overrides zero exit status"
assert_contains "$FAILED_IPC_OUT" 'integrity case failed' "HIP IPC reports explicit data failure"

setup_fixture() {
    local mode="$1"
    FIXTURE="$(mktemp -d "$TMP_ROOT/fixture-$mode.XXXXXX")"
    BIN_DIR="$FIXTURE/bin"
    DEVICES_ROOT="$FIXTURE/sys/bus/pci/devices"
    DEVICE_TREE="$FIXTURE/sys/devices"
    mkdir -p "$BIN_DIR" "$DEVICES_ROOT" "$DEVICE_TREE"
    printf 'processor : 0\nmodel name : Intel Xeon E5-2697A v4\n' > "$FIXTURE/cpuinfo"
    : > "$FIXTURE/cmdline"
    : > "$FIXTURE/dmesg"
    if [[ "$mode" == passthrough-conflict ]]; then
        printf 'BOOT_IMAGE=fixture iommu=pt\n' > "$FIXTURE/cmdline"
    fi
    printf '0000:00:00.0 Host bridge: Intel 8086:6f00\n' > "$FIXTURE/host-bridges"
    printf '8086:6f00\n' > "$FIXTURE/pci_p2pdma"

    add_pci_device() {
        local bdf="$1" target="$2" class="$3" mask="${4:-}"
        mkdir -p "$target"
        printf '%s\n' "$class" > "$target/class"
        if [[ -n "$mask" ]]; then printf '%s\n' "$mask" > "$target/dma_mask_bits"; fi
        ln -s "$target" "$DEVICES_ROOT/$bdf"
    }

    add_pci_device 0000:00:00.0 "$DEVICE_TREE/pci0000:00/0000:00:00.0" 0x060000
    add_pci_device 0000:00:02.0 "$DEVICE_TREE/pci0000:00/0000:00:02.0" 0x060400
    add_pci_device 0000:00:03.0 "$DEVICE_TREE/pci0000:00/0000:00:03.0" 0x060400
    add_pci_device 0000:04:00.0 "$DEVICE_TREE/pci0000:00/0000:00:02.0/0000:04:00.0" 0x060400
    add_pci_device 0000:07:00.0 "$DEVICE_TREE/pci0000:00/0000:00:03.0/0000:07:00.0" 0x060400
    add_pci_device 0000:05:00.0 "$DEVICE_TREE/pci0000:00/0000:00:02.0/0000:04:00.0/0000:05:00.0" 0x030000 44

    if [[ "$mode" == unknown-mask ]]; then
        add_pci_device 0000:08:00.0 "$DEVICE_TREE/pci0000:00/0000:00:03.0/0000:07:00.0/0000:08:00.0" 0x030000
    elif [[ "$mode" == same-root-port ]]; then
        add_pci_device 0000:08:00.0 "$DEVICE_TREE/pci0000:00/0000:00:02.0/0000:07:00.0/0000:08:00.0" 0x030000 44
    elif [[ "$mode" == different-host ]]; then
        printf '0000:00:00.0 Host bridge: Intel 8086:6f00\n0001:00:00.0 Host bridge: Intel 8086:6f00\n' > "$FIXTURE/host-bridges"
        add_pci_device 0001:00:03.0 "$DEVICE_TREE/pci0001:00/0001:00:03.0" 0x060400
        add_pci_device 0001:07:00.0 "$DEVICE_TREE/pci0001:00/0001:00:03.0/0001:07:00.0" 0x060400
        add_pci_device 0001:08:00.0 "$DEVICE_TREE/pci0001:00/0001:00:03.0/0001:07:00.0/0001:08:00.0" 0x030000 44
    else
        add_pci_device 0000:08:00.0 "$DEVICE_TREE/pci0000:00/0000:00:03.0/0000:07:00.0/0000:08:00.0" 0x030000 44
    fi

    cat > "$BIN_DIR/lspci" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *"-d 8086:6f00"*) cat "$FIXTURE/host-bridges" ;;
    *"-d 1002:7551"*) printf '0000:05:00.0 VGA compatible controller\n0000:08:00.0 VGA compatible controller\n' ;;
    *"-s 0000:00:02.0"*|*"-s 0001:00:02.0"*) echo 'Express Root Port' ;;
    *"-s 0000:00:03.0"*|*"-s 0001:00:03.0"*) echo 'Express Root Port' ;;
    *"-s 0000:04:00.0"*|*"-s 0000:07:00.0"*|*"-s 0001:07:00.0"*) echo 'Express Downstream Port' ;;
    *"-d 8086:"*) echo 'Intel Host bridge' ;;
    *) : ;;
esac
EOF
    cat > "$BIN_DIR/lscpu" <<'EOF'
#!/usr/bin/env bash
echo 'Socket(s): 1'
EOF
    cat > "$BIN_DIR/uname" <<'EOF'
#!/usr/bin/env bash
echo fixture-kernel
EOF
    cat > "$BIN_DIR/journalctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$FIXTURE_MODE" != "missing-logs" ]]; then
    if [[ "$FIXTURE_MODE" == "passthrough-conflict" ]]; then
        echo 'Default domain type: Translated'
    else
        echo 'fixture kernel log available'
    fi
fi
exit 0
EOF
    chmod +x "$BIN_DIR"/*
}

run_diagnose() {
    local mode="$1" mock_gpu_count="${2:-2}" mock_iommu="${3-TRANSLATED}" gpu1_bdf="${4:-0000:08:00.0}" output
    setup_fixture "$mode"
    output="$(PATH="$BIN_DIR:$PATH" \
        FIXTURE="$FIXTURE" \
        FIXTURE_MODE="$mode" \
        DIAGNOSE_PROC_CPUINFO="$FIXTURE/cpuinfo" \
        DIAGNOSE_PROC_CMDLINE="$FIXTURE/cmdline" \
        DIAGNOSE_DMESG_LOG="$FIXTURE/dmesg" \
        DIAGNOSE_SYSFS_PCI_DEVICES_ROOT="$DEVICES_ROOT" \
        DIAGNOSE_PCI_P2PDMA_DEBUGFS="$FIXTURE/pci_p2pdma" \
        TEST_MOCK_GPU1_BDF="$gpu1_bdf" \
        TEST_MODE=YES TEST_MOCK_GPU_COUNT="$mock_gpu_count" TEST_MOCK_IOMMU="$mock_iommu" \
        TEST_MOCK_HIP_IPC=PASS TEST_MOCK_TRANSFERBENCH=PASS TEST_MOCK_RCCL=PASS \
        "$REPO_ROOT/scripts/diagnose.sh" --full 2>&1)"
    printf '%s\n' "$output"
}

GOOD_TOPOLOGY_OUT="$(run_diagnose good)"
assert_contains "$GOOD_TOPOLOGY_OUT" 'GPU0 Upstream Root Port: 0000:00:02.0' "root port is resolved from the sysfs ancestry"
assert_contains "$GOOD_TOPOLOGY_OUT" 'GPU1 Upstream Root Port: 0000:00:03.0' "second root port is resolved"
assert_contains "$GOOD_TOPOLOGY_OUT" 'Host Bridge Domain:      SAME' "same host bridge is verified"
assert_contains "$GOOD_TOPOLOGY_OUT" 'DIRECT_P2P_READY = TEST_ONLY' "all mocks remain test only"
assert_contains "$GOOD_TOPOLOGY_OUT" 'TEST_MODE = YES' "mock run is visibly marked"
assert_not_contains "$GOOD_TOPOLOGY_OUT" $'DIRECT_P2P_READY = YES\n' "mocked success cannot become production ready"

SAME_PORT_OUT="$(run_diagnose same-root-port)"
assert_contains "$SAME_PORT_OUT" 'SAME_ROOT_PORT' "same root port blocks cross-port readiness"
assert_contains "$SAME_PORT_OUT" 'DIRECT_P2P_READY = NO' "same root port fails the cross-port target"

DIFFERENT_HOST_OUT="$(run_diagnose different-host 2 TRANSLATED 0001:08:00.0)"
assert_contains "$DIFFERENT_HOST_OUT" 'Host Bridge Domain:      DIFFERENT' "different host bridges are distinguished"
assert_contains "$DIFFERENT_HOST_OUT" 'DIRECT_P2P_READY = NO' "different host bridges fail closed"

MISSING_GPU_OUT="$(run_diagnose good 1)"
assert_contains "$MISSING_GPU_OUT" 'dual GPU required' "one GPU is insufficient"
assert_contains "$MISSING_GPU_OUT" 'DIRECT_P2P_READY = NO' "insufficient GPUs fail closed"

UNKNOWN_IOMMU_OUT="$(run_diagnose good 2 UNKNOWN)"
assert_contains "$UNKNOWN_IOMMU_OUT" 'P2P_PREREQUISITES = INCONCLUSIVE' "unknown IOMMU remains inconclusive"
assert_contains "$UNKNOWN_IOMMU_OUT" 'DIRECT_P2P_READY = INCONCLUSIVE' "unknown IOMMU cannot produce READY"

PASSTHROUGH_IOMMU_OUT="$(run_diagnose good 2 PASSTHROUGH)"
assert_contains "$PASSTHROUGH_IOMMU_OUT" 'IOMMU:        Passthrough' "passthrough configuration is detected"
assert_contains "$PASSTHROUGH_IOMMU_OUT" 'DIRECT_P2P_READY = INCONCLUSIVE' "untraced passthrough request behavior is inconclusive"

MISSING_LOGS_OUT="$(run_diagnose missing-logs)"
assert_contains "$MISSING_LOGS_OUT" 'kernel error log is unavailable' "empty kernel log is not treated as clean"
assert_contains "$MISSING_LOGS_OUT" 'DIRECT_P2P_READY = INCONCLUSIVE' "missing health evidence cannot produce READY"

PASSTHROUGH_CMDLINE_OUT="$(run_diagnose passthrough-conflict 2 '')"
assert_contains "$PASSTHROUGH_CMDLINE_OUT" 'IOMMU:        Passthrough (iommu=pt active)' "explicit passthrough cmdline takes precedence"
assert_contains "$PASSTHROUGH_CMDLINE_OUT" 'DIRECT_P2P_READY = INCONCLUSIVE' "contradictory log cannot make passthrough look validated"

UNKNOWN_MASK_OUT="$(run_diagnose unknown-mask)"
assert_contains "$UNKNOWN_MASK_OUT" 'DMA mask could not be read' "unknown DMA mask remains inconclusive"
assert_contains "$UNKNOWN_MASK_OUT" 'DIRECT_P2P_READY = INCONCLUSIVE' "unknown DMA mask cannot produce READY"

set +e
MOCK_WITHOUT_TEST_MODE_OUT="$(TEST_MOCK_TRANSFERBENCH=PASS "$REPO_ROOT/scripts/diagnose.sh" 2>&1)"
MOCK_WITHOUT_TEST_MODE_STATUS=$?
set -e
assert_equal 2 "$MOCK_WITHOUT_TEST_MODE_STATUS" "mock inputs require explicit TEST_MODE"
assert_contains "$MOCK_WITHOUT_TEST_MODE_OUT" 'refusing ambiguous mock execution' "ambiguous mocks are refused"

echo "OFFLINE_TESTS=PASS"
echo "ASSERTIONS=$PASS_COUNT"
