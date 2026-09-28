# Contributing to x99-amd-gpu-p2p

Thank you for your interest in improving PCIe P2P support on older workstation and server platforms!

## Ground Rules
1. **Evidence-Based Contributions**:
   - Any report of P2P success or regression must include exact kernel version, CPU model, motherboard BIOS version, GPU models, IOMMU status, and dmesg/journalctl error audits.
2. **Conservative Kernel Patching**:
   - We do not accept blind broad whitelist additions without evidence that the hardware actually routes peer traffic cleanly without silent data corruption or bus lockups.
3. **No Secret or Proprietary Data**:
   - Ensure all submitted logs, topologies, and benchmarks have local usernames, internal hostnames, and IP addresses redacted.
4. **Developer Certificate of Origin (DCO)**:
   - All contributions must comply with standard open-source Developer Certificate of Origin (Signed-off-by).
