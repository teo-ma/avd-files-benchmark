# Azure Files 成本估算：140 份 Share × 300 TB 总容量（Azure China 21Vianet）

> **价格参考**：<https://www.azure.cn/en-us/pricing/details/storage/files/>
> （Provisioned v2 / HDD / LRS，截取 2025-11-05 更新价格）

## 一、目标配置

| 维度 | 值 |
|---|---|
| Share 数量 | **140** 个 |
| 合计容量 | **300 TB = 307,200 GiB**（1 TB = 1024 GiB） |
| 每 Share 容量 | 307,200 / 140 ≈ **2,194.3 GiB**（≈ 2.14 TiB） |
| 每 Share 预配 IOPS | **3,000**（与本次实测样本一致） |
| 每 Share 预配带宽 | **100 MiB/s**（与本次实测样本一致） |
| 媒介 / 冗余 | **HDD（Standard）/ LRS** |
| 计费模式 | **Provisioned v2** |

说明：本次实测的 `share1tb`（1 TiB / 3000 IOPS / 100 MiB/s）即代表了本配置的性能基线。

## 二、单价（来自官方价格页，Azure China）

| 计量项 | 单价 | 备注 |
|---|---|---|
| 预配存储（HDD LRS） | **¥ 0.000102 / GiB / 小时** | — |
| 预配 IOPS（HDD LRS） | **¥ 0.000558 / IOPS / 小时** | **HDD 无 3000 IOPS 免费额度**，全部按单价收费 |
| 预配吞吐（HDD LRS） | **¥ 0.000834 / (MiB/s) / 小时** | **HDD 无免费额度**，全部按单价收费 |

> **重要说明**：官方价格页 "First 3000 IOPS at no additional cost" 仅列在 **SSD（Premium）列**，**HDD（Standard）没有任何 IOPS 或带宽的免费额度**。本方案选的是 HDD，因此 3000 IOPS 和 100 MiB/s 全部按单价收费。参见第六节 SSD 对比。

参考月按 **744 小时**（官方价格页注明口径）。

## 三、单 Share / 月 成本明细

> 2194 GiB × 0.000102 × 744 ＋ 3000 × 0.000558 × 744 ＋ 100 × 0.000834 × 744

| 项目 | 公式 | ¥ / 月 |
|---|---|---:|
| 存储 | 2194 × 0.000102 × 744 | **166.50** |
| IOPS | 3000 × 0.000558 × 744 | **1,245.46** |
| 吞吐 | 100 × 0.000834 × 744 | **62.05** |
| **每 Share 小计** | — | **≈ ¥ 1,474.01 / 月** |

## 四、140 Share 合计成本

| 时间跨度 | 金额 |
|---|---:|
| 每 Share / 月 | ¥ 1,474.01 |
| **140 Share / 月** | **≈ ¥ 206,361** |
| 140 Share / 年（×12） | **≈ ¥ 2,476,336** |

### 4.1 拆分结构

| 计量项 | 占比 |
|---|---:|
| 预配存储 | **≈ 11.3%** |
| 预配 IOPS | **≈ 84.5%**（主要成本） |
| 预配吞吐 | **≈ 4.2%** |

IOPS 是绝对主导成本，存储和吞吐占比相对较小。

## 五、不同配置组合下的月成本敏感性

假设 140 Share / 300 TB 不变，仅调整 IOPS/带宽两档参数：

| 方案 | IOPS | 带宽 MiB/s | 单 Share ¥/月 | 140 Share ¥/月 |
|---|---:|---:|---:|---:|
| **方案 A（基线，本次实测）** | 3,000 | 100 | 1,474 | **206,361** |
| 方案 B（仅保留基础 IOPS） | 1,000 | 50 | 166.5 + 415.2 + 31 = 612.7 | **85,782** |
| 方案 C（保读写 IOPS，带宽降一半） | 3,000 | 50 | 166.5 + 1,245.5 + 31 = 1,443 | **202,020** |
| 方案 D（加强型） | 6,000 | 150 | 166.5 + 2,490.9 + 93 = 2,750 | **385,058** |

> 结论：**IOPS 是成本杠杆**。在 AVD 用户盘场景下，若单用户对 IOPS 需求不高（典型桌面办公），可大幅削减 IOPS 预配以节省开支。

### 5.1 独享 Session Host 单用户场景（推荐）

**场景**：每台 Session Host 只分配 1 个用户（独享），H: 盘主要用于个人文档、配置缓存等；客户核心需求是**吞吐 100 MiB/s**（例如偶发大文件读写），对 IOPS 没有明确要求。

AVD 个人盘的稳态 IOPS 通常只有数十，峰值（Office 启动、打开大文档）也很少持续超过 500。**3000 IOPS 对单用户是严重过配**。HDD Provisioned v2 允许的 **IOPS 最小值 = 500**。

| 方案 | IOPS | 带宽 MiB/s | 单 Share ¥/月 | 140 Share ¥/月 | 140 Share ¥/年 | vs 基线 |
|---|---:|---:|---:|---:|---:|---:|
| 基线（方案 A） | 3,000 | 100 | 1,474.01 | 206,361 | 2,476,336 | — |
| **E. 推荐（1000 IOPS）** | **1,000** | **100** | **643.70** | **90,118** | **1,081,420** | **−56%** |
| **F. 极致省（500 IOPS，最小值）** | **500** | **100** | **436.13** | **61,058** | **732,697** | **−70%** |

公式：`存储 2194×0.000102×744 + IOPS N×0.000558×744 + 带宽 100×0.000834×744`

**保留 100 MiB/s 带宽**即可满足客户核心需求；IOPS 降到 1000 甚至 500 基本不影响单用户交互体验，因为：
1. Provisioned v2 支持 IOPS 积分突发（Credit-based），空闲时累积积分，峰值时可短时超出基线。
2. 本次 DiskSpd 4K 测试能跑到 7500+ IOPS，那是 **QD=32** 的人造压测；单用户交互几乎不可能触发这个并发。
3. IOPS 支持**在线热调**：先上 1000，观察 Azure Monitor 指标 `Transactions`（即已用 IOPS），不够随时上调。

**调整命令**：
```bash
az storage share-rm update \
  --storage-account <sa> --name <share> \
  --provisioned-iops 1000 --provisioned-bandwidth 100 \
  -g <rg>
```

**监控建议（上线后 1–2 周）**：
```bash
az monitor metrics list \
  --resource /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<sa>/fileServices/default/fileShares/<share> \
  --metric Transactions --aggregation Maximum Average --interval PT1H
```
若最大 IOPS < 300 → 可降到最小 500；若常顶到 800+ → 该 Share 单独调回 1500。

## 六、与 SSD (Premium) 价格对比

若改用 SSD Provisioned v2（¥ 0.001392 / GiB / 小时，IOPS 含 3000 免费，带宽含 3000 IOPS 对应免费额度）：

| 项目 | 公式 | ¥ / 月 |
|---|---|---:|
| 存储（SSD） | 2194 × 0.001392 × 744 | **2,272.07** |
| 预配 IOPS（含 3000 免费） | (3000 − 3000) × 0.000378 × 744 | **0.00** |
| 预配吞吐（100 MiB/s，3000 IOPS 免费额度通常包含 ≥125 MiB/s 吞吐） | 视免费额度 | **0** 或极少 |
| **每 Share 小计** | — | **≈ ¥ 2,272 / 月** |
| **140 Share / 月** | — | **≈ ¥ 318,080** |
| 140 Share / 年 | — | **≈ ¥ 3,816,960** |

> 备注：SSD 的 "First 3000 IOPS at no additional cost" 政策对 IOPS 需求 ≤3000 的场景非常友好；但存储单价是 HDD 的 13.6 倍。**当容量大、IOPS 诉求不高（≤3000）时，SSD 反而在某些场景下更昂贵。**

## 七、与 Provisioned v1（HDD 无该选项，仅 SSD）对比

Provisioned v1 仅 SSD：**¥ 1.626 / GiB / 月**

| 项目 | 公式 | ¥ / 月 |
|---|---|---:|
| 存储（单 Share 2194 GiB） | 2194 × 1.626 | **3,567.44** |
| 140 Share / 月 | — | **≈ ¥ 499,442** |

v1 中 IOPS 和吞吐固定绑定到存储规模，如需更高性能要再加预配，价格最高。**不推荐** 用于该方案。

## 八、总结

| 方案 | 月成本 | 年成本 | 适用性 |
|---|---:|---:|---|
| **HDD / Provisioned v2（基线）** | **¥ 206K** | **¥ 2.48M** | ★ 推荐：性价比最佳，性能已实测满足典型 AVD 用户盘 |
| HDD / Prov v2（方案 B 降配） | ¥ 86K | ¥ 1.03M | 轻度办公、对 IOPS 不敏感 |
| SSD / Provisioned v2 | ¥ 318K | ¥ 3.82M | 延迟敏感型应用（DB、CAD 工作集） |
| SSD / Provisioned v1 | ¥ 499K | ¥ 5.99M | 不推荐 |

### 建议

1. **优先选择 HDD Provisioned v2（方案 A）**：本次实测已验证其性能（读 148 MiB/s / 写 120 MiB/s / 4K IOPS 7568/6607）完全满足 AVD 用户盘场景。
2. **预算敏感时**可评估单用户真实 IOPS 峰值，按 1000–2000 IOPS 预配（方案 B）可将月成本降到 ¥ 86K 量级。
3. **从计费粒度优化**：IOPS 和吞吐支持**热更改**，日常低谷期可以下调预配（如非工作日降为 1000 IOPS），月成本可动态降低 40–60%。
   ```bash
   az storage share-rm update -g rg-avd-haier-20260312 \
     --storage-account <sa> --name <share> \
     --provisioned-iops 1000 --provisioned-bandwidth 50
   ```
4. **考虑单账户多 Share 部署**：单个 StandardV2 FileStorage 账户支持多个 Provisioned v2 共享，140 个 Share 可分布在 ~14 个存储账户（每账户 10 个 Share，避免账户级限额）。
5. 本估算不包含：出站数据流量、快照、跨区复制、客户端连接费用等；Azure Files 入站流量免费。

### 附：价格页截取（2025-11-05 更新）

| 计量（Provisioned v2 / LRS） | SSD（Premium） | HDD（Standard） |
|---|---|---|
| Storage | ¥0.001392 /GiB/hr | ¥0.000102 /GiB/hr |
| IOPS | ¥0.000378 /IOPS/hr **（前 3000 IOPS 免费）** | ¥0.000558 /IOPS/hr **（无免费额度）** |
| Throughput | ¥0.000546 /(MiB/s)/hr（随 3000 IOPS 附带基础带宽） | ¥0.000834 /(MiB/s)/hr **（无免费额度）** |

**关键区别**："First 3000 IOPS at no additional cost" 是 **SSD 独有** 的福利；HDD 的 3000 IOPS 和任何带宽都要计费。这也解释了为什么在 ≤3000 IOPS 且容量不大的场景下，SSD 反而可能比 HDD 便宜。

> 以上数值若与实际 Azure 发票有差异，请以 Azure 定价计算器和发票为准。
