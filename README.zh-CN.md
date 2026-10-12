# x99-amd-gpu-p2p

[English](README.md) | 简体中文

**在 Intel Broadwell-EP (X99) 与 AMD RDNA4 GPU 上实现 Linux P2PDMA、直接 HIP IPC 与 RCCL 集合通信加速**

---

## 概述

本项目记录了 Linux P2PDMA 变更、诊断工具、架构证据和基准结果，用于说明同一 Intel Broadwell-EP 主机桥下、跨 Root Port 的 AMD GPU **点对点 (P2P) PCIe 传输**。v0.2.0 维护更新将上游状态、参考硬件实测和仍未证明的机制分别说明。

2026-10-07，Linux PCI 维护者表示 `8086:6f00` P2PDMA 补丁已应用到 `pci/p2pdma` 开发树，目标为 v7.4 合并窗口。截至 2026-10-12 的核查，它尚未出现在 Linus 当前主线或任何已发布内核中。详见[上游状态](docs/upstream-status.md)；维护者应用不等于合并或发布。

参考 Ubuntu 6.8 系统使用本地白名单补丁、原生 44-bit AMDGPU DMA 掩码和 VT-d Translated 配置，TransferBench SDMA/Push 记录了**每个方向约 10.29 GB/s**，RCCL Rank-2 AllReduce 记录约 **9.49 GB/s 总线带宽**。二者是不同工作负载和指标。BAR 地址高于报告的 44-bit 掩码，但仓库没有捕获完整 DMA-BUF → IOMMU → GPUVM → PCIe 请求地址链路。实测成功并不能证明某个具体 IOVA 映射，也不能证明所有系统都必须使用 IOMMU 转换模式；见[高地址 P2P 调查](docs/high-address-p2p-investigation.md)。

---

## v0.2.0 P2P 实测验证指标

本表中的证据标签仅适用于所列 v0.2.0 P2P 实测指标；这些指标对应可复查的原始实测证据。该标签不适用于单独记录的 v0.3.0 推理观察，后者的证据等级为 `SUMMARY_ONLY`。

| 基准测试 | 原生基准 (Stock Baseline) | 直接 P2P (本项目) | 指标说明 | 原始证据来源 |
| :--- | :--- | :--- | :--- | :--- |
| **TransferBench P2P (SDMA/Push)** | 公开证据中未包含 | **10.29 GB/s** | 单向传输带宽 | `examples/broadwell-r9700/transferbench.txt` |
| **RCCL Ring AllReduce (256–1024 MiB)** | SGLang A/B 日志记录 SHM transport | **9.49 GB/s** | Rank-2 总线带宽，不是单向 peer-copy 速率 | `examples/broadwell-r9700/rccl.txt` |
| **HIP IPC 跨进程共享** | 公开证据中未包含 | **双向数据完整性** | 1 MiB、16 MiB、64 MiB 案例 | `examples/broadwell-r9700/hip-ipc.txt` |
| **SGLang Qwen3.8 TP2 (C=1 解码)** | 30.93 tok/s (via SHM) | **31.28 tok/s** (Direct P2P) | 单请求自回归解码吞吐 | `results/x99-r9700-qwen38.md` |
| **SGLang Qwen3.8 TP2 (C=4 解码)** | 69.41 tok/s (via SHM) | **71.10 tok/s** (Direct P2P) | 并发 4 聚合解码吞吐 | `results/x99-r9700-qwen38.md` |
| **内核错误样本** | 无配对基线 | **观察到 0 次** | 存档时间段内没有 AER/DMAR 故障 | `examples/broadwell-r9700/kernel-errors.txt` |

*参考平台：单路 Intel Xeon E5-2697A v4 (Broadwell-EP)，2x AMD Radeon AI PRO R9700 (RDNA4 gfx1201)，ROCm 7.2.4，Ubuntu 24.04 / patched Ubuntu 6.8。Prefill A/B 结果并不一致：1K 中位数 +32.1%、4K −3.7%、16K +0.5%、32K +25.5%；试验次数和完整区间见[结果表](results/x99-r9700-qwen38.md)。*

## v0.3.0 推理研究——有限证据结果

推理研究与 v0.2.0 P2P 通信结果分开记录。P5B-R 保存了 Plain / MTP / DFlash2 在 8K、32K、64K 下的解码速率汇总值，证据等级为 **`SUMMARY_ONLY`**。目前没有定位到逐轮样本，也没有已验证的聚合方法，因此这些数值不是可独立复现的 benchmark，也不能证明是中位数。32K DFlash2 的存储值为 **55.39 tok/s**；公式复算为 **55.395043 tok/s**，常规两位小数四舍五入为 **55.40 tok/s**。原始报告的舍入规则未知。详见[FP8 TP2 性能审计](docs/sglang-fp8-tp2-performance.md)。

| 上下文 | Plain | MTP | DFlash2 |
| --- | ---: | ---: | ---: |
| 8K | 21.48 | 42.29 | 51.44 |
| 32K | 19.21 | 45.32 | 55.39 |
| 64K | 16.82 | 28.60 | 59.81 |

P7 证据包含一次 **224000 输入 token** 的 TP2 请求，HTTP 200、`finish_reason=stop`、`semantic_pass=true`；实际生成 token 数缺失，因此无法计算输出吞吐率。**229000 输入 token** 请求虽然返回 HTTP 200，但以 `finish_reason=abort`、`semantic_pass=false` 结束，分类为 `PARTIAL_OR_ABORTED`；已审阅日志记录本次软件栈和配置在超过 **227701 tokens** 时拒绝请求。HTTP 请求成功不等于推理成功。**128K 和 192K 结果未纳入本次 Option B 已审计证据集**；此处不对其他尚未审阅的历史实验作判断。当前已审阅证据未能证明 256K 推理成功；配置的上下文上限不等于完成一次 256K 请求。详见[长上下文边界报告](docs/sglang-long-context-boundaries.md)。

MTP 和 DFlash2 属于推理软件栈模式，其性能差异**不能归因于 P2P 加速**。P5B 的模型/权重、软件版本、构建身份和逐轮配置来源仍未验证。

---

## 关键技术说明

1. **内核 DMA 掩码与 "dma44"**：
   经过验证的内核**不包含任何自定义 44-bit DMA 补丁**。AMDGPU 原生使用其默认的 `DMA_BIT_MASK(44)`。历史上本地内核构建标签中的 `dma44` 字符串仅作为一个构建里程碑标识符保留，源自更早之前测试并回滚的不稳定 48-bit DMA 修改实验。不需要也不存在任何自定义 GMC 驱动修改。
2. **IOMMU 寻址与因果关系**：
   参考采集显示 BAR0 地址高于报告的原生 44-bit DMA 掩码，并记录了 VT-d Translated 配置下的成功测试。现有材料没有跟踪对端 DMA-BUF 映射经过 IOMMU、GPUVM 到 GPU 实际请求地址的完整链路。Translated 是已测试配置；它的具体作用以及其他系统的要求仍未确定。详见[DMA 证据说明](docs/dma-addressing.md)。
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
│   │   └── upstream/       # 维护者已应用状态与历史材料
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
│   ├── sglang-qwen38-case-study.md # 实测推理案例研究
│   ├── upstream-status.md  # Linux PCI/P2PDMA 日期状态
│   └── high-address-p2p-investigation.md # DMA44 证据和未决问题
├── results/
│   ├── x99-r9700-qwen38.md # SGLang A/B 完整区间
│   └── evidence-manifest.json # 工件哈希与证据边界
├── tests/                  # 离线 fail-closed 与证据验证
├── .github/workflows/      # 仅运行离线检查的 CI
├── RELEASE_NOTES_v0.2.0.md # v0.2.0 发布说明
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

### Linux 上游状态

维护者表示补丁已应用到 `pci/p2pdma`，目标为 v7.4。截至 2026-10-12，尚未进入 Linus 当前主线或已发布内核。原 Ubuntu 6.8 验证补丁仍单独保留。详见[上游状态](docs/upstream-status.md)和[`patches/linux/upstream/`](patches/linux/upstream/README.md)。

---

## 配置直接 P2P：就绪检查关卡

直接 P2P AllReduce 需要依次通过三个不同层级的关卡（在参考 Broadwell-EP + RCCL `2.27.7` / `rocm-7.2.0` 测试平台上验证）：

1. **平台寻址能力（参考系统范围）**：
   - 参考采集记录了高地址 BAR、原生 44-bit 设备 DMA 掩码和 VT-d Translated 配置下的成功测试。完整地址映射链尚未捕获；不要将此配置要求外推到其他系统。
2. **内核子系统关卡**：
   - Linux 内核 `pci_p2pdma_whitelist[]`（`drivers/pci/p2pdma.c`）中必须包含 Intel Broadwell-EP `8086:6f00`，并带有 `REQ_SAME_HOST_BRIDGE` 标志。
3. **RCCL 用户态拓扑图关卡**：
   - 本地兼容性补丁针对 RCCL 2.27.7 / `rocm-7.2.0` 源码；develop 和正式版本状态已单独复核，见[RCCL 兼容说明](docs/rccl.md)。
   - 对需要此补丁的构建，可设置 `NCCL_P2P_LEVEL=PHB` 并确认日志中的直接 P2P 标志：
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
- [Linux 上游状态](docs/upstream-status.md)
- [高地址 P2P 调查](docs/high-address-p2p-investigation.md)
- [证据清单](results/evidence-manifest.json)
- [v0.2.0 Release Notes](RELEASE_NOTES_v0.2.0.md)
- [v0.3.0 Release Notes](RELEASE_NOTES_v0.3.0.md)
- [SGLang Qwen3.8-27B 实测推理案例研究](docs/sglang-qwen38-case-study.md)
- [SGLang FP8 TP2 性能审计](docs/sglang-fp8-tp2-performance.md)
- [SGLang 长上下文边界](docs/sglang-long-context-boundaries.md)

---

## 许可证与致谢

- 本项目原创文档、脚本与测试结果均遵循 [MIT License](LICENSE)。
- Linux 内核补丁遵循 `GPL-2.0-only` 许可证（详见 [LICENSES/README.md](LICENSES/README.md)）。
- RCCL 补丁为针对 `src/graph/paths.cc` 的衍生 diff，受上游 BSD-3-Clause 许可证管辖，版权归 (c) Advanced Micro Devices, Inc. 及 NVIDIA Corporation 所有。
