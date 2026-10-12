# Intel Broadwell-EP (8086:6f00) & Linux P2PDMA Whitelist

## The Linux P2PDMA Gating Mechanism
In the Linux kernel PCIe subsystem (`drivers/pci/p2pdma.c`), peer-to-peer DMA between devices connected to different PCIe Root Ports is strictly gated by a whitelist table: `pci_p2pdma_whitelist[]`.

When two PCIe endpoints request peer DMA mapping via `calc_map_type_and_dist()`:
1. The kernel determines whether traffic between the provider and client must traverse the PCIe Host Bridge / Root Complex (`map_through_host_bridge`).
2. If the data path traverses the host bridge, the kernel checks whether the CPU supports P2PDMA natively (`cpu_supports_p2pdma()`) or whether the Host Bridge device ID is listed in `pci_p2pdma_whitelist[]` (`host_bridge_whitelist()`).
3. **If the host bridge is absent and the CPU is not natively P2PDMA-capable**:
   The kernel sets `map_type = PCI_P2PDMA_MAP_NOT_SUPPORTED` and rejects peer DMA mapping.
4. **If the host bridge is present in the whitelist**:
   The kernel can return `PCI_P2PDMA_MAP_THRU_HOST_BRIDGE` for an eligible pair. This clears a Linux P2PDMA topology gate; downstream DMA-BUF, DMA API, and device mappings are separate layers.

---

## Upstream State (checked 2026-10-12)

The PCI maintainer reported that the `8086:6f00` patch had been applied to the `pci/p2pdma` development tree for the v7.4 merge window on 2026-10-07. This is a maintainer-applied patch, not yet evidence of a merge to Linus or a released kernel. At the last check, the current mainline source did not contain `8086:6f00`, and kernel.org listed `7.3-rc6` as the latest mainline release candidate. See [the dated upstream status record](upstream-status.md) for links and milestone definitions.

The current-mainline whitelist still includes prior-generation Intel Haswell-EP host bridges:
```c
/* Intel Xeon E7 v3/Xeon E5 v3/Core i7 */
{PCI_VENDOR_ID_INTEL, 0x2f00, REQ_SAME_HOST_BRIDGE},
{PCI_VENDOR_ID_INTEL, 0x2f01, REQ_SAME_HOST_BRIDGE},
```
At the check date, Broadwell `8086:6f00` was absent from Linus' current mainline file, although the PCI maintainer had applied the submitted change to the subsystem tree. Do not equate that state with a released kernel. The exact runtime map decision also depends on the device pair and kernel topology; use the diagnostics and capture it on the target host.

---

## The Validated Fix
To enable peer DMA routing on Broadwell-EP, the patch adds:
```c
/* Intel Xeon E7 v4/Xeon E5 v4 */
{PCI_VENDOR_ID_INTEL, 0x6f00, REQ_SAME_HOST_BRIDGE},
```
With this entry present:
* The kernel verifies that both endpoints share the same host bridge (`REQ_SAME_HOST_BRIDGE`).
* The Linux P2PDMA topology gate can return the through-host-bridge mapping type for an eligible pair.
* The reference patched Ubuntu 6.8 system recorded ~10.29 GB/s per-direction TransferBench SDMA/Push results and zero AER/DMAR faults in the archived interval. This is a platform-specific observation, not a general guarantee about all devices or mappings.
