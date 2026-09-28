# Validated Linux Kernel Patch

## Overview
This directory contains the exact patch that was applied, built, and thoroughly validated on the reference hardware testbed.

> [!IMPORTANT]
> **This is the patch that was validated on the reference system.**
> It is based on Ubuntu 24.04 LTS kernel source and is separate from the upstream Linux candidate patch.

## Metadata
* **Base Repository**: `https://git.launchpad.net/~ubuntu-kernel/ubuntu/+source/linux/+git/noble`
* **Base Tag**: `Ubuntu-6.8.0-139.139` (Kernel `6.8.12`)
* **Base Git SHA**: `78d7d3da9419bebf9c91d65c6268db56a705445e`
* **Target File**: `drivers/pci/p2pdma.c`
* **Patch File**: `0001-pci-p2pdma-add-broadwell-6f00-host-bridge.patch`
* **Validated Hardware**:
  * Motherboard: HUANANZHI X99-TF GAMING V6.0
  * CPU: Intel Xeon E5-2697A v4 @ 2.60GHz (Single-socket Broadwell-EP, Host Bridge `8086:6f00`)
  * GPUs: Dual AMD Radeon AI PRO R9700 (32 GiB GDDR6, gfx1201) in PCIe 3.0 x16 slots
* **Validation Date**: 2026-09-14 / 2026-09-15
* **Validation Evidence**:
  * TransferBench SDMA / GFX Push: ~10.29 GB/s bidirectional throughput
  * RCCL AllReduce: ~9.49 GB/s bus bandwidth (large size sweep 1M-1024M)
  * HIP IPC: 100% data verification across 1M, 16M, and 64M transfers
  * Error Counters: 0 DMAR faults, 0 PCIe AER errors, 0 GPU resets, 0 ring timeouts

## What This Patch Changes
It adds a single table entry into `pci_p2pdma_whitelist[]`:
```c
{PCI_VENDOR_ID_INTEL, 0x6f00, REQ_SAME_HOST_BRIDGE},
```
This informs the Linux PCI core subsystem that device `8086:6f00` (Intel Xeon E7 v4 / E5 v4 Host Bridge) can safely route peer-to-peer DMA between root ports under the same host bridge.

## Known Limitations
* **Single Host Bridge Only**: Transactions are restricted to endpoints under the same host bridge (`REQ_SAME_HOST_BRIDGE`). P2P across multiple CPU sockets (QPI traversal) is NOT whitelisted.
* **Driver Mask Requirements**: Requires either an IOMMU in Translated mode (`DMA-FQ`) or physical BAR placement within the device's DMA mask range.
