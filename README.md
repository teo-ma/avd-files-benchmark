# AVD Azure Files Benchmark

> 在 **Azure Virtual Desktop (AVD) Session Host** 上一键复现 Azure Files（SMB, Provisioned v2）吞吐量 + IOPS 基准测试。

本仓库包含：
- 一键式 PowerShell 基准脚本（`scripts/Run-Benchmark.ps1`）
- 工具预置脚本（将 DiskSpd 预先上传到 Azure Files 供离线拉取）
- 远程触发入口（macOS/Linux 上用 `az vm run-command` 调起）
- **已执行完成的测试报告**（`docs/Benchmark-Report.md`）
- **140 份 Share × 300 TB 容量的 Azure China 21v 成本估算**（`docs/Cost-Analysis.md`）

## 快速开始

### 方法 A：从本地（macOS/Linux）远程触发（推荐）

```bash
git clone https://github.com/teo-ma/avd-files-benchmark.git
cd avd-files-benchmark

# 登录 Azure China
az cloud set --name AzureChinaCloud
az login
az account set --subscription af1c9543-5759-41cb-9291-cb91be45ea0e

export AZ_RG=rg-avd-haier-20260312
export AZ_VM=avd-gpu-u6                    # 目标 Session Host
export SA=stavdhaieru6h01                  # 存储账户
export SHARE=share1tb                      # 文件共享
export KEY="$(az storage account keys list -g $AZ_RG -n $SA --query '[0].value' -o tsv)"

./scripts/invoke-remote-benchmark.sh
# 运行约 ~18 分钟；结果保存到 /tmp/benchmark-*.json
```

### 方法 B：在 Session Host（Windows PowerShell）直接运行

1. RDP 登入 Session Host（以管理员身份打开 PowerShell）
2. 下载 `Run-Benchmark.ps1`
   ```powershell
   # 直接从本 GitHub repo 下载
   Invoke-WebRequest `
     -Uri 'https://raw.githubusercontent.com/teo-ma/avd-files-benchmark/main/scripts/Run-Benchmark.ps1' `
     -OutFile C:\Tools\Run-Benchmark.ps1 -UseBasicParsing
   ```
3. 执行
   ```powershell
   $key = '<你的 storage account key>'
   Set-ExecutionPolicy -Scope Process Bypass -Force
   C:\Tools\Run-Benchmark.ps1 `
     -StorageAccount stavdhaieru6h01 `
     -ShareName share1tb `
     -AccountKey $key `
     -ResultFile 'C:\Tools\bench-result.json'
   ```

### 方法 C：预置 DiskSpd 到 Azure Files（离线场景）

在没有外网出口的 Session Host 上，先把 `diskspd.exe` 预传到共享的 `tools/` 目录，`Run-Benchmark.ps1` 会优先从共享拉取。

```powershell
# 在一台有外网访问的 Windows 机器上执行一次即可
.\scripts\Upload-DiskSpdToShare.ps1 `
  -StorageAccount stavdhaieru6h01 `
  -ShareName share1tb `
  -AccountKey '<KEY>'
```

之后 `Run-Benchmark.ps1` 会自动：
1. 检查 `C:\Tools\diskspd\diskspd.exe`
2. 若不存在，先临时映射共享尝试 `\\share\tools\diskspd.exe`
3. 若仍找不到，fallback 到 GitHub 下载

## 测试矩阵

| ID | 文件大小 | 块大小 | 读写比 | 说明 |
|---|---|---|---|---|
| 10M-RR-64K | 10 MB | 64 KiB | 100% 读 | 小文件随机读带宽 |
| 10M-RW-64K | 10 MB | 64 KiB | 100% 写 | 小文件随机写带宽 |
| 10M-MIX-64K | 10 MB | 64 KiB | 70/30 | 小文件混合 |
| 100M-RR-64K | 100 MB | 64 KiB | 100% 读 | 中等文件随机读 |
| 100M-RW-64K | 100 MB | 64 KiB | 100% 写 | 中等文件随机写 |
| 100M-MIX-64K | 100 MB | 64 KiB | 70/30 | 中等文件混合 |
| 1G-RR-64K | 1 GB | 64 KiB | 100% 读 | 大文件随机读（稳态） |
| 1G-RW-64K | 1 GB | 64 KiB | 100% 写 | 大文件随机写（稳态） |
| 1G-MIX-64K | 1 GB | 64 KiB | 70/30 | 大文件混合（稳态） |
| 1G-RR-4K | 1 GB | 4 KiB | 100% 读 | IOPS 读参考 |
| 1G-RW-4K | 1 GB | 4 KiB | 100% 写 | IOPS 写参考 |

统一参数：`-d30 -W5 -t4 -o8 -r -L -Sh`（QD=32，随机访问，直通）。

## 输出

- **JSON**：结构化结果，字段 `Id / Label / MiBps / IOPS / AvgLat_ms / P95Read_ms / P95Write_ms`
- **Table**：人类可读表格
- （可选）`-ResultFile` 参数可将 JSON 落盘到指定路径

示例（本次 `avd-gpu-u6` 实测）：

```
Id           Label                        MiBps  IOPS    AvgLat_ms P95Read_ms P95Write_ms
--           -----                        -----  ----    --------- ---------- -----------
10M-RR-64K   10MB / RandRead  / 64K       138.05 2208.80 14.522    25.846     N/A        
100M-RR-64K  100MB / RandRead  / 64K      147.95 2367.24 13.388    18.506     N/A        
1G-RR-64K    1GB / RandRead  / 64K        141.94 2271.09 14.098    12.870     N/A        
1G-RW-64K    1GB / RandWrite / 64K        120.03 1920.49 16.652    N/A        85.844     
1G-MIX-64K   1GB / 70R30W    / 64K        167.44 2679.02 11.787    50.364     46.753     
1G-RR-4K     1GB / RandRead  / 4K  (IOPS) 29.56  7568.05 4.219     4.907      N/A        
1G-RW-4K     1GB / RandWrite / 4K  (IOPS) 25.81  6606.66 4.842     N/A        8.091      
```

完整报告：
- [docs/Benchmark-Report.md](docs/Benchmark-Report.md) — 基线 3000 IOPS / 100 MiB/s 压测
- [docs/Benchmark-Report-500IOPS.md](docs/Benchmark-Report-500IOPS.md) — 优化方案 500 IOPS / 100 MiB/s 压测
- [docs/Benchmark-Report-Customer-Scenarios.md](docs/Benchmark-Report-Customer-Scenarios.md) — **客户真实场景验收（CAD 加载 / 大文件拷贝 / Office）** ⭐

原始 JSON：
- [results/avd-gpu-u6-2026-04-21.json](results/avd-gpu-u6-2026-04-21.json)（3000 IOPS 压测）
- [results/avd-gpu-u6-2026-04-22-500iops.json](results/avd-gpu-u6-2026-04-22-500iops.json)（500 IOPS 压测）
- [results/avd-gpu-u6-2026-04-22-customer-500iops.json](results/avd-gpu-u6-2026-04-22-customer-500iops.json)（500 IOPS 客户场景）

## 三种测试 Profile

```powershell
# Customer（推荐给客户）：7 项真实场景验收（CAD / 大文件 / Office）
.\scripts\Run-Benchmark.ps1 -StorageAccount <sa> -ShareName <share> -AccountKey '<key>' -TestProfile Customer

# Quick：3 项快速巡检（2 分钟）
.\scripts\Run-Benchmark.ps1 ... -TestProfile Quick

# Full：11 项高压力压测（默认，工程师诊断用）
.\scripts\Run-Benchmark.ps1 ... -TestProfile Full
```

## 本次样本的共享配置

| 项目 | 值 |
|---|---|
| 存储账户 | `stavdhaieru6h01`（StandardV2_LRS / HDD） |
| Share | `share1tb` |
| 容量 | 1 TiB (1024 GiB) |
| 预配 IOPS | 3,000（突发 9,000） |
| 预配带宽 | 100 MiB/s |
| 协议 | SMB 3.x（加密） |

## 成本

**场景**：140 Share × 300 TB（每 Share ≈ 2.14 TiB，100 MiB/s 吞吐），HDD Provisioned v2 LRS。

| 方案 | IOPS | 月成本 | 年成本 | 说明 |
|---|---:|---:|---:|---|
| 基线 | 3000 | ¥206,361 | ¥2,476,336 | 最初配置 |
| **推荐（已实测）** | **500** | **¥61,058** | **¥732,697** | **−70%**；独享 Session Host 场景客户体验无感 |

**客户核心需求（100 MiB/s 吞吐）在 500 IOPS 下完全满足**（实测 131–161 MiB/s），详见 [Benchmark-Report-500IOPS.md](docs/Benchmark-Report-500IOPS.md)。

详细拆分、敏感性分析、SSD/v1 对比：[docs/Cost-Analysis.md](docs/Cost-Analysis.md)

## 目录结构

```
avd-files-benchmark/
├── README.md                          # 本文件（测试指南）
├── docs/
│   ├── Benchmark-Report.md            # 完整测试报告
│   └── Cost-Analysis.md               # 140 Share × 300TB 成本分析
├── scripts/
│   ├── Run-Benchmark.ps1              # 一键基准脚本（在 Session Host 执行）
│   ├── Upload-DiskSpdToShare.ps1      # 预置 DiskSpd 到 Azure Files
│   └── invoke-remote-benchmark.sh     # macOS/Linux 远程触发入口
└── results/
    └── avd-gpu-u6-2026-04-21.json     # 本次基线结果
```

## 先决条件

- 目标 Session Host 可通过 SMB 访问 Azure Files endpoint（默认端口 445 出站）
- 至少具备 Storage Account Key（或 RBAC + SMB Kerberos/AAD Kerberos 身份，但本脚本以 Account Key 为基础）
- `az cli` 已登录 Azure China Cloud（用于方法 A）
- Session Host 本地磁盘 ≥ 2 GB 空闲（用于存放 DiskSpd 和测试文件）

## 许可

MIT
