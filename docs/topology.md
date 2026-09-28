# PCIe Topology & Bus Hierarchy

## Physical & Logical Topology

```text
Intel Xeon E5-2697A v4 (Socket 0, NUMA node 0)
└── PCIe Root Complex / host-bridge domain [8086:6f00]
    ├── Root Port 00:02.0 [8086:6f04] (PCIe 3.0 x16 @ 8.0 GT/s)
    │   └── AMD PCIe bridge function 1002:1478 / 1002:1479
    │       ├── AMD Radeon AI PRO R9700 [1002:7551] (0000:05:00.0, GPU 0)
    │       └── AMD Audio Function [1002:ab40] (0000:05:00.1)
    │
    └── Root Port 00:03.0 [8086:6f08] (PCIe 3.0 x16 @ 8.0 GT/s)
        └── AMD PCIe bridge function 1002:1478 / 1002:1479
            ├── AMD Radeon AI PRO R9700 [1002:7551] (0000:08:00.0, GPU 1)
            └── AMD Audio Function [1002:ab40] (0000:08:00.1)
```

> [!NOTE]
> **PCI Database Label Clarification**:
> In standard Linux `lspci` outputs, devices `1002:1478` and `1002:1479` may appear with the string `"Navi 10 XL Upstream/Downstream Port of PCI Express Switch"`.
> The "Navi 10 XL" string is simply the PCI ID database label for this integrated AMD PCIe bridge function and **does not describe the R9700 GPU architecture** (which is RDNA4 / gfx1201).
> The motherboard itself does not contain a Navi switch; this bridge is physically integrated on the R9700 add-in card.

## Key Verified Topology Facts

1. **`SAME_CPU = YES`**:
   - Both GPUs connect to physical slots wired to the single Intel Xeon CPU socket.
   - There is no multi-socket NUMA crossing or QPI interconnect involved.
2. **`SAME_HOST_BRIDGE_DOMAIN = YES`**:
   - Both Root Ports (`00:02.0` and `00:03.0`) are anchored by Host Bridge `0000:00:00.0` (`[8086:6f00]`).
3. **`DIFFERENT_ROOT_PORTS = YES`**:
   - GPU0 is behind Root Port 2; GPU1 is behind Root Port 3.
   - P2P traffic cannot be switched downstream of the root ports; it must traverse the CPU Host Bridge.
