# Intel Broadwell-EP (8086:6f00) & Linux P2PDMA Whitelist

## The Linux P2PDMA Gating Mechanism
In the Linux kernel PCIe subsystem (`drivers/pci/p2pdma.c`), peer-to-peer DMA between devices connected to different PCIe Root Ports is strictly gated by a whitelist table: `pci_p2pdma_whitelist[]`.

When two PCIe endpoints request peer DMA mapping:
1. The kernel determines the lowest common upstream bridge (provider) connecting the requester and provider devices.
2. If this common provider is a Root Complex / Host Bridge (identified via `pci_host_bridge_dev()`), the kernel checks whether its PCI Vendor and Device IDs match an entry in `pci_p2pdma_whitelist[]`.
3. If the host bridge is not present in the whitelist, the kernel marks the path as `PCI_P2PDMA_MAP_THRU_HOST_BRIDGE` (or rejects it), preventing peer memory mapping.

## Upstream State
In upstream Linux mainline (`master` branch at commit `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`, checked 2026-09-28), the whitelist includes prior-generation Intel Haswell-EP host bridges:
```c
/* Intel Xeon E7 v3/Xeon E5 v3/Core i7 */
{PCI_VENDOR_ID_INTEL, 0x2f00, REQ_SAME_HOST_BRIDGE},
{PCI_VENDOR_ID_INTEL, 0x2f01, REQ_SAME_HOST_BRIDGE},
```
However:
* **Broadwell `8086:6f00` is not present in the current P2PDMA whitelist.**
* Consequently, on Broadwell-EP systems (Xeon E5 v4 series, Intel X99 / C612 chipset), Linux defaults to disallowing peer DMA across root ports.

## The Validated Fix
To enable peer DMA routing on Broadwell-EP, the validated patch adds:
```c
/* Intel Xeon E7 v4/Xeon E5 v4 */
{PCI_VENDOR_ID_INTEL, 0x6f00, REQ_SAME_HOST_BRIDGE},
```
With this entry present:
* The kernel verifies that both endpoints share the same host bridge (`REQ_SAME_HOST_BRIDGE`).
* Direct peer DMA is permitted between root ports.
* On the reference Intel Xeon E5-2697A v4 system, this enabled ~10.29 GB/s bidirectional throughput across root ports with zero errors.
