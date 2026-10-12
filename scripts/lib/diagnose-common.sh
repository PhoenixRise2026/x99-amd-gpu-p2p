#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

get_pci_root_bus() {
    local bdf="$1"
    local path base

    path="$(readlink -f "${SYSFS_PCI_DEVICES_ROOT}/${bdf}" 2>/dev/null)" || return 1
    while [[ -n "$path" && "$path" != "/" ]]; do
        base="${path##*/}"
        if [[ "$base" =~ ^pci([[:xdigit:]]{4}):([[:xdigit:]]{2})$ ]]; then
            printf '%s:%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]'
            return 0
        fi
        path="${path%/*}"
    done
    return 1
}

get_upstream_root_port() {
    local bdf="$1"
    local path base class info

    path="$(readlink -f "${SYSFS_PCI_DEVICES_ROOT}/${bdf}" 2>/dev/null)" || return 1
    path="${path%/*}"
    while [[ -n "$path" && "$path" != "/" ]]; do
        base="${path##*/}"
        if [[ "$base" =~ ^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}\.[[:xdigit:]]$ ]]; then
            class="$(cat "${SYSFS_PCI_DEVICES_ROOT}/${base}/class" 2>/dev/null || true)"
            if [[ "$class" == 0x0604* ]]; then
                info="$(lspci -D -s "$base" -vv 2>/dev/null || true)"
                if printf '%s\n' "$info" | grep -Eiq 'Root Port'; then
                    printf '%s\n' "$base"
                    return 0
                fi
            fi
        fi
        path="${path%/*}"
    done
    return 1
}

find_6f00_host_bridge_for_root_bus() {
    local root_bus="$1"
    local line bdf

    while IFS= read -r line; do
        bdf="${line%%[[:space:]]*}"
        if [[ "$bdf" =~ ^([[:xdigit:]]{4}:[[:xdigit:]]{2}):[[:xdigit:]]{2}\.[[:xdigit:]]$ ]] &&
           [[ "$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')" == "$root_bus" ]]; then
            printf '%s\n' "$bdf"
            return 0
        fi
    done < <(lspci -D -d 8086:6f00 2>/dev/null || true)
    return 1
}

classify_rccl_output() {
    local output="$1"
    local exit_status="${2:-0}"

    if [[ "$exit_status" -ne 0 ]] || printf '%s\n' "$output" | grep -Eiq 'via SHM|isAllDirectP2p[[:space:]]+0|P2P direct disabled|P2P disabled'; then
        printf 'FAIL\n'
    elif ! printf '%s\n' "$output" | grep -Eiq 'isAllDirectP2p[[:space:]]+1'; then
        printf 'INCONCLUSIVE\n'
    elif ! printf '%s\n' "$output" | grep -Eiq 'via[[:space:]]+P2P/IPC'; then
        printf 'INCONCLUSIVE\n'
    else
        printf 'PASS\n'
    fi
}
