# Validated Linux Kernel Patch

## Overview
This directory contains the exact patch used for the archived reference-hardware tests.

> [!IMPORTANT]
> **This is the patch used for the archived reference-system tests.**
> It is based on Ubuntu 24.04 LTS kernel source and is separate from the upstream patch artifact.

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
  * TransferBench SDMA / GFX Push: ~10.29 GB/s per-direction unidirectional peer throughput
  * RCCL AllReduce: ~9.49 GB/s bus bandwidth (large size sweep 1M-1024M)
  * HIP IPC: 100% data verification across 1M, 16M, and 64M transfers
  * Archived error sample: 0 DMAR faults, 0 PCIe AER errors, 0 GPU resets, 0 ring timeouts in the reported interval

## What This Patch Changes
It adds a single table entry into `pci_p2pdma_whitelist[]`:
```c
{PCI_VENDOR_ID_INTEL, 0x6f00, REQ_SAME_HOST_BRIDGE},
```
This marks `8086:6f00` as eligible for the Linux through-host-bridge P2PDMA map path when the kernel's same-host-bridge condition is met. The entry is a topology whitelist assertion; it does not prove the DMA address-translation chain.

## Known Limitations
* **Single Host Bridge Only**: Transactions are restricted to endpoints under the same host bridge (`REQ_SAME_HOST_BRIDGE`). P2P across multiple CPU sockets (QPI traversal) is NOT whitelisted.
* **Address-translation boundary**: The recorded test used Intel VT-d Translated mode with the stock 44-bit AMDGPU mask. The public artifacts do not trace the complete peer BAR → DMA-BUF/DMA API → IOMMU → GPUVM → PCIe request path, so they do not establish a general IOMMU requirement or prove the IOVA used for every transfer. See [the investigation](../../../docs/high-address-p2p-investigation.md).
