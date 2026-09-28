#!/usr/bin/env bash
#
# collect-topology.sh - Read-only PCIe topology collector
#
set -euo pipefail

echo "=== System PCIe Tree ==="
lspci -tv

echo
echo "=== Host Bridge & Root Port Detail ==="
lspci -nn -s 00:00.0
lspci -nn -s 00:02.0
lspci -nn -s 00:03.0

echo
echo "=== GPU Device Detail ==="
lspci -nn -d 1002:7551
