# Azure Files 1 TB Share — Office 真实场景测试（1000 IOPS / 120 MiB/s）

> 在升级后的配额下，重测 Customer Profile 中 **Office 编辑** 与 **Office 保存** 两个核心工作负载。

## 一、测试环境

| 项 | 值 |
|---|---|
| 测试日期 | 2026-04-22 |
| Azure 云 | Azure China（21Vianet） |
| 区域 | chinanorth3 |
| 存储账户 | `stavdhaieru6h01`（FileStorage StandardV2_LRS, HDD） |
| Share | `share1tb`（1024 GiB） |
| **Provisioned IOPS** | **1000** |
| **Provisioned Bandwidth** | **120 MiB/s** |
| Included Burst IOPS | 5000 |
| Session Host | `avd-gpu-u6`（NC8as_T4_v3, Win11 Ent） |
| 挂载 | `T:`（SMB 3.1.1, SYSTEM 全局映射） |
| 工具 | DiskSpd v2.2.0 |
| 每项时长 | 30 秒（+3 秒 warmup） |

## 二、测试工作负载

| 编号 | 场景映射 | 文件 | 块 | 模式 | 读写 | 线程 | QD | DiskSpd |
|---|---|---|---:|---|---|---:|---:|---|
| 1G-MIX-64K-LQ | **Office 编辑**（打开+编辑+自动保存）| 1 GiB | 64 KiB | 随机 | 70% R / 30% W | 2 | 2 | `-b64K -t2 -o2 -r -w30 -d30 -W3 -L -Sh` |
| 100M-SW-64K | **Office 保存**（小文档落盘）| 100 MiB | 64 KiB | 顺序 | 100% W | 2 | 2 | `-b64K -t2 -o2 -si -w100 -d30 -W3 -L -Sh` |

> 低队列深度（总并发 = 2×2 = 4）刻意模拟真实桌面办公场景，不堆高 QD 做压测。

## 三、测试结果

| 场景 | IOPS | 吞吐 (MiB/s) | 平均延迟 (ms) | P95 (ms) | P99 (ms) |
|---|---:|---:|---:|---:|---:|
| **Office 编辑** (1G-MIX-64K-LQ) | **867.6** | **54.23** | **4.61** | **9.98** | **18.67** |
| **Office 保存** (100M-SW-64K)   | **710.3** | **44.39** | **5.63** | — | — |

\* "—" 表示 DiskSpd 仅单侧操作（100% W）时未输出合并百分位。

## 四、结果解读

### 4.1 IOPS 与 Provisioned 的关系

- Office 编辑 **867 IOPS** ≈ 接近但未超过 Provisioned 1000。稳态完全由 Provisioned 配额承担，**没有吃 Burst**。
- Office 保存 **710 IOPS**，同样在稳态范围内。
- 两个场景都未触发限流，说明 Office 级别的工作流在 1000 IOPS 配额下**有约 130–300 IOPS 的安全余量**。

### 4.2 吞吐量与带宽的关系

- 编辑 54.2 MiB/s，保存 44.4 MiB/s，距离 120 MiB/s 带宽上限还有 2× 以上空间。
- 带宽在此类负载下**不是瓶颈**，资源配置合理。

### 4.3 延迟体验

- 编辑场景：平均 4.6 ms，P95 10 ms，P99 18.7 ms — 用户感知 **打开/保存 Office 文档在 < 100 ms**（单文件约 20–50 IO），几乎无感。
- 保存场景：平均 5.6 ms — 100 MB 文档理论保存时间 `100/44.39 ≈ 2.3 秒`，符合本地盘体验。

### 4.4 与 4K 随机 IO 对比

| 维度 | 4K RR QD=32 | 1G-MIX-64K-LQ (本次) |
|---|---:|---:|
| IOPS | 5124（吃 Burst） | 867（稳态） |
| 吞吐 | 20.0 MiB/s | **54.2 MiB/s** |
| 块大小 | 4 KiB | 64 KiB |
| 瓶颈 | IOPS | 无（均在配额内） |

**印证前面的结论**：一旦块大小从 4K 提升到 64K，吞吐立刻翻 2.7 倍，且 IOPS 反而降低。真实 Office 场景（64K+ 顺序/近顺序）**不会踩 IOPS 红线**。

### 4.5 与 500 IOPS 版本对比

| 场景 | 500 IOPS 结果 | **1000 IOPS 结果** | 变化 |
|---|---|---|---|
| Office-Edit (1G-MIX-64K-LQ) | 56.12 MiB/s / 5.9 ms / P95 10.8 ms | **54.23 MiB/s / 4.6 ms / P95 10.0 ms** | 吞吐持平，**延迟 −22%** |
| Office-Save (100M-SW-64K) | 12.27 MiB/s / — | **44.39 MiB/s / 5.6 ms** | **+261% 吞吐** |

- **Office 保存暴涨**：500 IOPS 下 12 MiB/s 就意味着保存 IO 被限流严重（196 IOPS × 64K = 12.3 MiB/s）；1000 IOPS 下完全放开，710 IOPS × 64K = 44 MiB/s。说明 **500 IOPS 对多人并发保存有风险，1000 IOPS 是合适的工作点**。
- Office 编辑变化不大：因为 500 IOPS 下也不是瓶颈（当时实测 870+ IOPS，说明配额对偶发 burst 有弹性）。

## 五、容量与延迟预算

以客户典型单租户每日使用估算：

| 活动 | 单次 IO 量 | 单用户/天 | 140 并发用户/天 | 占用 IOPS 稳态 |
|---|---:|---:|---:|---:|
| 打开 100MB 图纸 | 1600 IO | 5 次 | 8000 IO | < 1% |
| Word 编辑（自动保存） | 50 IO/次 | 30 次 | 4200 IO | < 1% |
| 保存 100MB 文档 | 1600 IO | 3 次 | 4800 IO | < 1% |
| 合计 | — | — | 17,000 IO/天 | ≈ 0.2 IOPS 平均 |

**结论**：1000 Provisioned IOPS 给单个 Share + 单个租户的日常 Office 工作流**有 100× 以上的裕量**。瓶颈只会出现在极端并发场景（例：140 人同时保存大文件 → 理论峰值 9,000 IOPS，需要 Burst credits 顶 ~1 小时）。

## 六、一键复现

```powershell
# 管理员 PowerShell，avd-gpu-u6 已预置脚本
cd C:\Tools\benchmark
Set-ExecutionPolicy -Scope Process Bypass -Force

# 完整 Customer Profile（含本报告的两项及另外 5 项真实场景）
.\Run-Benchmark.ps1 -StorageAccount stavdhaieru6h01 -ShareName share1tb `
  -AccountKey '<KEY>' -TestProfile Customer
```

仅测本次两项（直接 DiskSpd）：

```powershell
# 先按本报告方法挂载 T: 并预创建 mix1g.dat / sw100m.dat
C:\Tools\diskspd\diskspd.exe -b64K -t2 -o2 -r -w30  -d30 -W3 -L -Sh T:\bench-office\mix1g.dat
C:\Tools\diskspd\diskspd.exe -b64K -t2 -o2 -si -w100 -d30 -W3 -L -Sh T:\bench-office\sw100m.dat
```

## 七、原始数据

- JSON: [results/avd-gpu-u6-2026-04-22-office-1000iops.json](../results/avd-gpu-u6-2026-04-22-office-1000iops.json)
- Share 当前配置: 1000 IOPS / 120 MiB/s / 5000 Burst / 1024 GiB

---

**总结**

| 项 | 结论 |
|---|---|
| Office 编辑 | ✅ 54 MiB/s, P99 18.7 ms — 用户无感 |
| Office 保存 | ✅ 44 MiB/s, 比 500 IOPS 版本快 **3.6×** |
| IOPS 预算 | ✅ 稳态用到 710–867，还有 13–29% 余量 |
| 带宽预算 | ✅ 仅占用上限的 37–45% |
| **是否需要再提配额？** | ❌ **不需要。1000 IOPS / 120 MiB/s 对此场景已足够，再加配置是浪费。** |
