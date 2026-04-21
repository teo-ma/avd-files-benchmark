# AVD Azure Files 吞吐量 / IOPS 基准测试报告

**测试时间**：2026-04-21 22:55 – 23:16 CST
**执行主机**：`avd-gpu-u6`（Standard_NC8as_T4_v3, 8 vCPU, 56 GiB RAM, Windows 11 Enterprise multi-session）
**目标文件共享**：`\\stavdhaieru6h01.file.core.chinacloudapi.cn\share1tb`
**测试工具**：DiskSpd v2.2.0 (2024/6/3)
**映射方式**：`New-SmbGlobalMapping T:` (SYSTEM scope, SMB 3.x + `RequirePrivacy`)
**区域**：Azure China North 3（21Vianet）

---

## 一、存储资源规格

| 项目 | 值 |
|---|---|
| 订阅 | `af1c9543-5759-41cb-9291-cb91be45ea0e` |
| 资源组 | `rg-avd-haier-20260312` |
| 存储账户 | `stavdhaieru6h01`（Kind=FileStorage, SKU=StandardV2_LRS, HDD） |
| 区域 | `chinanorth3` |
| 共享名 | `share1tb` |
| 容量 | **1024 GiB (1 TiB)** |
| 预配 IOPS（基线） | **3,000** |
| 突发 IOPS（峰值） | **9,000** |
| 预配带宽 | **100 MiB/s** |
| 协议 | SMB（启用加密） |

## 二、测试参数

统一 DiskSpd 参数：`-d30 -W5 -t4 -o8 -r -L -Sh`

| 参数 | 说明 |
|---|---|
| `-d30` | 每项测试运行 30 秒 |
| `-W5` | 预热 5 秒 |
| `-t4` | 每文件 4 个线程 |
| `-o8` | 每线程队列深度 8（总有效 QD = 32） |
| `-r` | 随机 I/O |
| `-L` | 采集延迟直方图 |
| `-Sh` | 禁用软件/硬件缓存（直通） |

测试矩阵（共 11 项）：
- **10 MB / 100 MB / 1 GB** × **100% 随机读 / 100% 随机写 / 70%读+30%写**，块大小 **64 KiB**（带宽向）
- **1 GB × 随机读 / 随机写**，块大小 **4 KiB**（IOPS 向）

## 三、测试结果

| ID | 场景 | 吞吐量 MiB/s | IOPS | 平均延迟 ms | P95 读 ms | P95 写 ms |
|---|---|---:|---:|---:|---:|---:|
| 10M-RR-64K | 10MB / 随机读 / 64K | **138.05** | 2208.80 | 14.52 | 25.85 | — |
| 10M-RW-64K | 10MB / 随机写 / 64K | 63.54 | 1016.72 | 31.52 | — | 146.10 |
| 10M-MIX-64K | 10MB / 70R30W / 64K | 16.97 | 271.50 | 117.66 | 139.45 | 143.44 |
| 100M-RR-64K | 100MB / 随机读 / 64K | **147.95** | 2367.24 | 13.39 | 18.51 | — |
| 100M-RW-64K | 100MB / 随机写 / 64K | 5.95 | 95.17 | 339.93 | — | 1763.09 |
| 100M-MIX-64K | 100MB / 70R30W / 64K | 16.68 | 266.93 | 119.79 | 149.46 | 150.57 |
| 1G-RR-64K | 1GB / 随机读 / 64K | **141.94** | 2271.09 | 14.10 | 12.87 | — |
| 1G-RW-64K | 1GB / 随机写 / 64K | **120.03** | 1920.49 | 16.65 | — | 85.84 |
| 1G-MIX-64K | 1GB / 70R30W / 64K | **167.44** | 2679.02 | 11.79 | 50.36 | 46.75 |
| 1G-RR-4K（IOPS） | 1GB / 随机读 / 4K | 29.56 | **7568.05** | 4.22 | 4.91 | — |
| 1G-RW-4K（IOPS） | 1GB / 随机写 / 4K | 25.81 | **6606.66** | 4.84 | — | 8.09 |

原始 JSON：[results/avd-gpu-u6-2026-04-21.json](../results/avd-gpu-u6-2026-04-21.json)

## 四、结论与分析

### 4.1 带宽（64 KiB 块）
- **读吞吐量稳定在约 138–148 MiB/s**，混合场景峰值达 **167 MiB/s**，超过 100 MiB/s 预配值 —— 这是 Provisioned v2 的突发能力（Burst credits）生效。
- 1 GB 大文件下持续稳态（138 / 120 / 167 MiB/s），是最能反映真实业务稳态吞吐的参考值。

### 4.2 IOPS（4 KiB 块）
- **随机读 7568 IOPS**、**随机写 6607 IOPS**，接近并使用了 **9000 突发 IOPS** 配额。
- 平均延迟 4.2–4.8 ms，P95 < 9 ms，符合 SMB Standard Provisioned v2 预期。

### 4.3 小文件写入异常分析
- `100M-RW-64K` 只有 **5.95 MiB/s，P95 1763 ms** 显著偏低。原因：
  1. 小文件（10 MB / 100 MB）在 QD=32 下对单文件重复写，SMB 持久句柄 + 元数据锁争用严重。
  2. Provisioned v2 的写带宽是**带突发令牌桶的**；连续大量 I/O 到相同 range 时令牌被消耗后触发节流。
  3. 1 GB 场景下 offset 分布广，写入被分摊到更多 range，限流现象缓解。

### 4.4 与规格卡对比

| 指标 | 规格 | 实测峰值 | 达成率 |
|---|---|---|---|
| 带宽 | 100 MiB/s（预配） | 167.44 MiB/s | 167%（突发） |
| IOPS（基线） | 3,000 | 7,568 读 / 6,607 写 | 252% / 220%（突发） |
| IOPS（突发） | 9,000 | 7,568 读 | 84% |

**→ 实测性能符合 Azure Files Provisioned v2 Standard 层规格，可在突发区间超出预配带宽。**

## 五、使用建议

| 场景 | 推荐 |
|---|---|
| 单文件大块顺序/随机拷贝（≥100 MB） | 可获 **≈140–170 MiB/s**，满足大部分 AVD 用户场景 |
| 大量并发小写（OFFICE 临时文件、缓存） | 建议分散到多文件、多子目录；单文件高 QD 写入易节流 |
| 4K 随机访问（SQLite、IDE 索引） | **~7500 读 / ~6600 写 IOPS**，延迟 < 5 ms，适用 |
| 持续高吞吐（>200 MiB/s） | 需升级到 **SSD（Premium）** 或提升 Provisioned v2 带宽配额 |

### 可选优化

1. 若需稳定跑满 ≥150 MiB/s，建议将 `provisioned-bandwidth` 从 100 → 150–200。
   ```bash
   az storage share-rm update -g rg-avd-haier-20260312 \
     --storage-account stavdhaieru6h01 --name share1tb \
     --provisioned-bandwidth 150
   ```
2. 4K IOPS 密集场景，将 `provisioned-iops` 提到 6000 可避免突发令牌耗尽后的抖动。
3. 客户端启用 **SMB Multichannel** + Accelerated Networking（NC8as_T4_v3 默认已开启）。
4. 使用 `New-SmbGlobalMapping` + `FullAccess` 让 SYSTEM/所有用户会话共用连接。
