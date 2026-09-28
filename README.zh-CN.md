# x99-amd-gpu-p2p

[English](README.md) | 简体中文

**在 Intel Broadwell-EP (X99) 与 AMD RDNA4 GPU 上实现 Linux P2PDMA、直接 HIP IPC 与 RCCL 集合通信加速**

---

## 概述

本项目提供经过验证的内核补丁、诊断脚本、架构文档与实测基准测试，用于在同一 Intel Broadwell-EP host-bridge / Root Complex 域内跨不同 PCIe Root Port 的 AMD GPU 之间启用**直接硬件点对点 (P2P) PCIe DMA 传输**。

历史上，Linux 内核 PCIe P2PDMA 允许 Haswell-EP 主机桥（`8086:2f00` / `8086:2f01`）跨 Root Port 执行 peer DMA，但其继任者 Broadwell-EP（`8086:6f00`）被上游白名单遗漏。因此，多 GPU AMD ROCm 工作负载（例如使用 RCCL 的 SGLang / vLLM 分布式 LLM 推理）被标记为 `PCI_P2PDMA_MAP_NOT_SUPPORTED`，迫使跨 GPU 通信回退到主机共享内存中转（`via SHM/direct/direct`）。

通过将 `8086:6f00` 添加至 Linux P2PDMA 白名单并确保正确的 IOMMU 地址转换，直接点对点传输在 TransferBench 中实现了**单向约 10.29 GB/s** 的带宽，在 RCCL AllReduce 中实现了 **9.49 GB/s** 的总线带宽，且系统内核零 AER/DMAR 故障。

---

## 实测验证指标

以下所有性能数据均严格基于可复查的原始实测证据：

| 基准测试 | 原生基准 (Stock Baseline) | 直接 P2P (本项目) | 指标说明 | 原始证据来源 |
| :--- | :--- | :--- | :--- | :--- |
| **TransferBench P2P (SDMA/Push)** | 回退 / 被拒绝 | **10.29 GB/s** | 单向传输带宽 | `examples/broadwell-r9700/transferbench.txt` |
| **RCCL Ring AllReduce (256–1024 MiB)** | 回退至 SHM | **9.49 GB/s** | 总线带宽 ($B_{\text{bus}} = B_{\text{alg}}$) | `examples/broadwell-r9700/rccl.txt` |
| **HIP IPC 跨进程共享** | 回退 / 被拒绝 | **Direct DMA-BUF Map** | 1M、16M、64M 双向正确性验证 | `examples/broadwell-r9700/hip-ipc.txt` |
| **SGLang Qwen3.8 TP2 (C=1 解码)** | 30.93 tok/s (via SHM) | **31.28 tok/s** (Direct P2P) | 单请求自回归解码吞吐 | `results/x99-r9700-qwen38.md` |
| **SGLang Qwen3.8 TP2 (C=4 解码)** | 69.41 tok/s (via SHM) | **71.10 tok/s** (Direct P2P) | 并发 4 聚合解码吞吐 | `results/x99-r9700-qwen38.md` |
| **内核总线稳定性** | 0 次错误 | **0 次错误** | 零 AER 错误，零 DMAR 故障 | `examples/broadwell-r9700/kernel-errors.txt` |

*参考平台：单路 Intel Xeon E5-2697A v4 (Broadwell-EP)，2x AMD Radeon AI PRO R9700 (RDNA4 gfx1201)，ROCm 7.2.4，Ubuntu 24.04 / Kernel 6.8。*

---

## 关键技术说明

1. **内核 DMA 掩码与 "dma44"**：
   经过验证的内核**不包含任何自定义 44-bit DMA 补丁**。AMDGPU 原生使用其默认的 `DMA_BIT_MASK(44)`。历史上本地内核构建标签中的 `dma44` 字符串仅作为一个构建里程碑标识符保留，源自更早之前测试并回滚的不稳定 48-bit DMA 修改实验。不需要也不存在任何自定义 GMC 驱动修改。
2. **IOMMU 寻址与因果关系（仅限参考系统范围）**：
   在经过验证的参考系统上，需要启用转换模式（Translated）VT-d 是因为该平台的对端 BAR 物理窗口被映射到了超出 GPU 原生 44-bit DMA 寻址物理范围的地址（例如 `0x3808_...` 这样的 46-bit MMIO 地址）。在转换模式（`intel_iommu=on`, `DMA-FQ`）下，IOMMU 会将对端访问动态重映射为紧凑的 IOVA，确保地址落在 44-bit DMA 掩码之内。这是该参考系统平台的物理布局特征，而非所有 X99 主板的普遍不变要求。若对端 BAR 资源物理映射已位于设备 DMA 掩码寻址范围内，其需求可能不同。
3. **AITER 与运行时后端**：
   在经过验证的 SGLang v0.5.18 环境中，未安装也未激活 AITER（`AITER_ACTIVE = NO`）。经验证的解码栈为 Triton/HIP 混合实现（Full Attention：Triton；GDN/recurrent：Triton；Tree-Verify：Triton；AWQ M>1：Triton；AWQ M=1：原生 HIP GEMV）。这仅描述经过验证的软件技术栈，不应解读为 gfx1201 硬件不支持 AITER。
4. **PCIe 桥设备标识字符串**：
   在 `lspci` 中，桥设备函数 `1002:1478/1479` 可能会显示 `"Navi 10 XL Upstream/Downstream Port of PCI Express Switch"` 标签。该 "Navi 10 XL" 字符串仅为 PCI ID 数据库对 AMD PCIe 桥/交换芯片函数 `1002:1478/1479` 的描述标签，并不代表 R9700 GPU 架构（其为 RDNA4 gfx1201）。
5. **拓扑分类与传输通道**：
   `PATH_PHB` 属于拓扑距离分类。当直接 P2P 资格被拒绝时，RCCL 会回退到 `SHM` 传输通道。应用 RCCL 覆写补丁并设置 `NCCL_P2P_LEVEL=PHB` 后，RCCL 授予 P2P 资格并选择 `via P2P/IPC` 通道。

---

## 仓库结构

```text
x99-amd-gpu-p2p/
├── README.md               # 英文主文档
├── README.zh-CN.md         # 简体中文说明文档
├── LICENSE                 # MIT 许可证
├── NOTICE.md               # 法律与第三方声明
├── SECURITY.md             # 安全策略与漏洞反馈
├── CONTRIBUTING.md         # 贡献与代码审查指南
├── LICENSES/               # 各组件特定许可证详情
├── patches/
│   ├── linux/
│   │   ├── validated/      # 经 Ubuntu 6.8.0-139 验证的内核补丁
│   │   └── upstream/       # 面向 Linux mainline git 准备的候选补丁
│   └── rccl/               # ROCm 7.2.0 RCCL 拓扑图 P2P 覆写补丁
├── docs/                   # 架构、拓扑与深入分析文档
│   ├── architecture.md     # 软硬件架构设计
│   ├── topology.md         # PCIe Root Complex 拓扑结构分析
│   ├── broadwell-p2pdma.md # Linux P2PDMA 白名单机制详解
│   ├── dma-addressing.md   # IOMMU、DMA 掩码与 IOVA 转换指南
│   ├── hip-ipc.md          # HIP IPC 验证方法与机制
│   ├── rccl.md             # RCCL 拓扑探测与 P2P 调优
│   ├── troubleshooting.md  # 综合故障排查与诊断指南
│   ├── version-matrix.md   # 完整软硬件版本与来源矩阵
│   └── sglang-qwen38-case-study.md # 实测推理案例研究
├── scripts/                # 自动化非破坏性检测脚本
│   ├── diagnose.sh         # Fail-closed 自动化诊断工具
│   ├── collect-topology.sh # 收集 PCIe 树与设备 BDF 拓扑
│   ├── check-pcie.sh       # 验证链路速度、宽度与 ACS 状态
│   ├── check-dma-addresses.sh # 检查 DMA 掩码与 IOMMU 组
│   ├── check-hip-ipc.sh    # HIP IPC 验证包装脚本
│   ├── run-transferbench.sh # 运行 TransferBench P2P 带宽测试
│   ├── run-rccl.sh         # 运行 rccl-tests AllReduce 基准测试
│   └── collect-errors.sh   # 检查 dmesg 中的 AER、DMAR 与 GPU 重置错误
├── examples/               # 验证服务器上的脱敏参考输出
│   └── broadwell-r9700/    # Intel Broadwell + 2x R9700 参考日志
├── results/                # 详细基准测试日志与数据表
│   └── x99-r9700-qwen38.md # SGLang Qwen3.8-27B-AWQ TP2 基准测试结果
└── third_party/            # 上游来源与许可证追踪
```

---

## 快速上手：诊断检测

克隆或复制本仓库，并执行 fail-closed 诊断检查：

```bash
chmod +x scripts/*.sh
./scripts/diagnose.sh
```

默认情况下，`diagnose.sh` 会检查平台先决条件（CPU 插槽、主机桥 `8086:6f00`、独立 Root Port、IOMMU 转换模式、PCIe 链路参数和错误计数器）。如果尚未执行活跃的对端传输测试，它将输出：
```text
P2P_PREREQUISITES = PASS
DIRECT_P2P_READY = INCONCLUSIVE
```

若要运行完整的对端基准测试（TransferBench、HIP IPC 与 RCCL）以判定最终 P2P 就绪状态：
```bash
./scripts/diagnose.sh --full
```

---

## 应用内核补丁

### 验证补丁 (`Ubuntu-6.8.0-139.139`)

此补丁专门在 `Ubuntu-6.8.0-139.139`（内核 `6.8.12`，Git SHA: `78d7d3da9419bebf9c91d65c6268db56a705445e`）上通过了完整验证。其他内核版本需要进行 rebase 并独立验证：
```bash
git apply patches/linux/validated/0001-pci-p2pdma-add-broadwell-6f00-host-bridge.patch
```

### 上游 Linux 主线候选补丁

面向上游 `torvalds/linux` master 准备的候选补丁以 unified diff 形式提供于：
`patches/linux/upstream/0001-broadwell-6f00-p2pdma-candidate.diff`。
- 基于 `torvalds/linux` master 提交 `72d3fcf802c45d00b300f25b848a93c3a2bd7c7e` rebase。
- 通过 `checkpatch.pl --strict` 检查（0 错误，0 警告）。
- 已通过 `get_maintainer.pl` 确定相应 maintainer。
- **状态**：面向后续上游提交准备的候选补丁。必须在 Broadwell-EP `8086:6f00` 参考主机或等效拓扑上执行功能验证。

---

## 配置直接 P2P：就绪检查关卡

直接 P2P AllReduce 需要依次通过三个不同层级的关卡（在参考 Broadwell-EP + RCCL `2.27.7` / `rocm-7.2.0` 测试平台上验证）：

1. **平台寻址能力（参考系统范围）**：
   - 在参考测试平台上，系统固件将 GPU 64-bit BAR 分配在物理 46-bit 地址空间；必须启用处于转换模式（`DMA-FQ`）的 Intel VT-d，将事务重映射为与 GPU 原生 44-bit DMA 掩码兼容的紧凑 IOVA。
   - 物理 BAR 分配已在设备 DMA 掩码范围内的系统，可能无需转换模式 IOMMU 域。
2. **内核子系统关卡**：
   - Linux 内核 `pci_p2pdma_whitelist[]`（`drivers/pci/p2pdma.c`）中必须包含 Intel Broadwell-EP `8086:6f00`，并带有 `REQ_SAME_HOST_BRIDGE` 标志。
3. **RCCL 用户态拓扑图关卡**：
   - 在原生 RCCL 2.27.7 中，硬编码的 Intel x86 平台启发式规则会无条件将 `p2pLevel` 降级为 `PATH_PXB`，忽略用户环境变量。
   - 本项目附带的 RCCL 补丁（`patches/rccl/0001-graph-honor-explicit-p2p-level-after-platform-limit.patch`）确保设置 `NCCL_P2P_LEVEL=PHB` 时能够成功授予跨 Root Port 传输的 P2P 资格：
   ```bash
   export NCCL_P2P_LEVEL=PHB
   export NCCL_DEBUG=INFO
   ```

---

## 文档索引

- [软硬件架构设计](docs/architecture.md)
- [PCIe Root Complex 拓扑结构分析](docs/topology.md)
- [Broadwell P2PDMA 白名单机制详解](docs/broadwell-p2pdma.md)
- [IOMMU 与 DMA 寻址指南](docs/dma-addressing.md)
- [HIP IPC 验证方法与机制](docs/hip-ipc.md)
- [RCCL 集合通信加速调优](docs/rccl.md)
- [综合故障排查与诊断指南](docs/troubleshooting.md)
- [完整软硬件版本与来源矩阵](docs/version-matrix.md)
- [SGLang Qwen3.8-27B 实测推理案例研究](docs/sglang-qwen38-case-study.md)

---

## 许可证与致谢

- 本项目原创文档、脚本与测试结果均遵循 [MIT License](LICENSE)。
- Linux 内核补丁遵循 `GPL-2.0-only` 许可证（详见 [LICENSES/README.md](LICENSES/README.md)）。
- RCCL 补丁为针对 `src/graph/paths.cc` 的衍生 diff，受上游 BSD-3-Clause 许可证管辖，版权归 (c) Advanced Micro Devices, Inc. 及 NVIDIA Corporation 所有。
