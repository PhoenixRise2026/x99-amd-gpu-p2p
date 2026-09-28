# Intel Broadwell-EP (8086:6f00) & Linux P2PDMA Whitelist

## The Linux P2PDMA Gating Mechanism
In the Linux kernel PCIe subsystem (`drivers/pci/p2pdma.c`), peer-to-peer DMA between devices connected to different PCIe Root Ports is strictly gated by a whitelist table: `pci_p2pdma_whitelist[]`.

When two PCIe endpoints request peer DMA mapping via `calc_map_type_and_dist()`:
1. The kernel determines whether traffic between the provider and client must traverse the PCIe Host Bridge / Root Complex (`map_through_host_bridge`).
2. If the data path traverses the host bridge, the kernel checks whether the CPU supports P2PDMA natively (`cpu_supports_p2pdma()`) or whether the Host Bridge device ID is listed in `pci_p2pdma_whitelist[]` (`host_bridge_whitelist()`).
3. **If the host bridge is absent from the whitelist**:
   The kernel sets `map_type = PCI_P2PDMA_MAP_NOT_SUPPORTED` and rejects peer DMA mapping.
4. **If the host bridge is present in the whitelist**:
   The kernel returns `PCI_P2PDMA_MAP_THRU_HOST_BRIDGE`, permitting the DMA-BUF framework to map peer BAR memory directly across the host bridge.

---

## Upstream State
In upstream Linux mainline (`master` branch at commit `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`, checked 2026-09-28), the whitelist includes prior-generation Intel Haswell-EP host bridges:
```c
/* Intel Xeon E7 v3/Xeon E5 v3/Core i7 */
{PCI_VENDOR_ID_INTEL, 0x2f00, REQ_SAME_HOST_BRIDGE},
{PCI_VENDOR_ID_INTEL, 0x2f01, REQ_SAME_HOST_BRIDGE},
```
However:
* **Broadwell `8086:6f00` is currently absent from the upstream P2PDMA whitelist.**
* Consequently, on Broadwell-EP systems (Xeon E5 v4 series, Intel X99 / C612 chipset), Linux defaults to returning `PCI_P2PDMA_MAP_NOT_SUPPORTED` for peer transactions across root ports.

---

## The Validated Fix
To enable peer DMA routing on Broadwell-EP, the patch adds:
```c
/* Intel Xeon E7 v4/Xeon E5 v4 */
{PCI_VENDOR_ID_INTEL, 0x6f00, REQ_SAME_HOST_BRIDGE},
```
With this entry present:
* The kernel verifies that both endpoints share the same host bridge (`REQ_SAME_HOST_BRIDGE`).
* Direct peer DMA is permitted across root ports with `PCI_P2PDMA_MAP_THRU_HOST_BRIDGE`.
* On the reference Intel Xeon E5-2697A v4 system, this enabled ~10.29 GB/s per-direction throughput across root ports with zero AER/DMAR errors.
