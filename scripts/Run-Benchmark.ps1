<#
.SYNOPSIS
  一键式 Azure Files (SMB) 基准测试脚本（DiskSpd）。
  可在 AVD Session Host 上直接执行，自动完成：
    1. 准备 DiskSpd（优先从目标共享的 tools/ 目录拷贝，fallback 联网下载）
    2. 以 SYSTEM 作用域映射到一个本地盘符
    3. 运行 11 项随机读/写/混合负载（10MB / 100MB / 1GB × 64K；1GB × 4K IOPS）
    4. 解析结果为 JSON + 表格输出
    5. 清理测试文件和映射

.PARAMETER StorageAccount
  存储账户名，例如 stavdhaieru6h01

.PARAMETER ShareName
  文件共享名，例如 share1tb

.PARAMETER AccountKey
  存储账户 key (key1 或 key2)

.PARAMETER DriveLetter
  测试过程中用于映射的盘符，默认 T:

.PARAMETER ResultFile
  可选：将 JSON 结果写入指定文件路径

.EXAMPLE
  .\Run-Benchmark.ps1 -StorageAccount stavdhaieru6h01 -ShareName share1tb -AccountKey 'xxxxx=='

.EXAMPLE
  # 在 az vm run-command 中批量执行
  az vm run-command invoke -g <RG> -n <VM> --command-id RunPowerShellScript `
    --scripts @Run-Benchmark.ps1 --parameters StorageAccount=<SA> ShareName=<SHARE> AccountKey=<KEY>
#>
param(
  [Parameter(Mandatory=$true)][string]$StorageAccount,
  [Parameter(Mandatory=$true)][string]$ShareName,
  [Parameter(Mandatory=$true)][string]$AccountKey,
  [string]$DriveLetter = 'T:',
  [string]$ResultFile  = ''
)
$ErrorActionPreference = 'Stop'

$ep       = "$StorageAccount.file.core.chinacloudapi.cn"
$remote   = "\\$ep\$ShareName"
$testDir  = "$DriveLetter\bench"
$toolsDir = 'C:\Tools\diskspd'
$exe      = Join-Path $toolsDir 'diskspd.exe'

# 1) Ensure DiskSpd on local disk
function Ensure-DiskSpd {
  if (Test-Path $exe) { return }
  New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null

  # 1a) Try pull from share (\\...\<ShareName>\tools\diskspd.exe) via a temp mapping
  $tmpLetter = 'Y:'
  $tmpMapped = $false
  try {
    Get-SmbGlobalMapping -ErrorAction SilentlyContinue |
      Where-Object { $_.LocalPath -eq $tmpLetter } |
      Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue
    $sec  = ConvertTo-SecureString $AccountKey -AsPlainText -Force
    $cred = [System.Management.Automation.PSCredential]::new("localhost\$StorageAccount", $sec)
    New-SmbGlobalMapping -LocalPath $tmpLetter -RemotePath $remote -Credential $cred `
      -Persistent $false -RequirePrivacy $true `
      -FullAccess @('NT AUTHORITY\SYSTEM','BUILTIN\Administrators') -ErrorAction Stop | Out-Null
    $tmpMapped = $true
    $srcExe = "$tmpLetter\tools\diskspd.exe"
    if (Test-Path $srcExe) {
      Copy-Item $srcExe -Destination $exe -Force
      Write-Host "[Ensure-DiskSpd] Copied from share: $srcExe"
    }
  } catch {
    Write-Host "[Ensure-DiskSpd] Share pull failed: $_"
  } finally {
    if ($tmpMapped) {
      Get-SmbGlobalMapping -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPath -eq $tmpLetter } |
        Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue
    }
  }
  if (Test-Path $exe) { return }

  # 1b) Fallback: GitHub
  $zip = Join-Path $env:TEMP 'DiskSpd.zip'
  $url = 'https://github.com/microsoft/diskspd/releases/download/v2.2/DiskSpd.zip'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 120
  Expand-Archive -Path $zip -DestinationPath "$toolsDir\_unz" -Force
  Copy-Item "$toolsDir\_unz\amd64\diskspd.exe" -Destination $exe -Force
  Remove-Item "$toolsDir\_unz" -Recurse -Force
  Remove-Item $zip -Force
  Write-Host "[Ensure-DiskSpd] Downloaded from GitHub"
}

Ensure-DiskSpd
if (-not (Test-Path $exe)) { throw "DiskSpd not available at $exe" }

# 2) Mount test drive (SYSTEM global mapping)
Get-SmbGlobalMapping -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPath -eq $DriveLetter } |
  Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue
$sec  = ConvertTo-SecureString $AccountKey -AsPlainText -Force
$cred = [System.Management.Automation.PSCredential]::new("localhost\$StorageAccount", $sec)
New-SmbGlobalMapping -LocalPath $DriveLetter -RemotePath $remote -Credential $cred `
  -Persistent $false -RequirePrivacy $true `
  -FullAccess @('NT AUTHORITY\SYSTEM','BUILTIN\Administrators') -ErrorAction Stop | Out-Null
New-Item -ItemType Directory -Path $testDir -Force | Out-Null

# 3) Workload matrix
$tests = @(
  @{ Id='10M-RR-64K';  File='f10M.dat';  Size=10485760;    Block=65536; Write=0;   Label='10MB / RandRead  / 64K' }
  @{ Id='10M-RW-64K';  File='f10M.dat';  Size=10485760;    Block=65536; Write=100; Label='10MB / RandWrite / 64K' }
  @{ Id='10M-MIX-64K'; File='f10M.dat';  Size=10485760;    Block=65536; Write=30;  Label='10MB / 70R30W   / 64K' }
  @{ Id='100M-RR-64K'; File='f100M.dat'; Size=104857600;   Block=65536; Write=0;   Label='100MB / RandRead  / 64K' }
  @{ Id='100M-RW-64K'; File='f100M.dat'; Size=104857600;   Block=65536; Write=100; Label='100MB / RandWrite / 64K' }
  @{ Id='100M-MIX-64K';File='f100M.dat'; Size=104857600;   Block=65536; Write=30;  Label='100MB / 70R30W   / 64K' }
  @{ Id='1G-RR-64K';   File='f1G.dat';   Size=1073741824;  Block=65536; Write=0;   Label='1GB / RandRead  / 64K' }
  @{ Id='1G-RW-64K';   File='f1G.dat';   Size=1073741824;  Block=65536; Write=100; Label='1GB / RandWrite / 64K' }
  @{ Id='1G-MIX-64K';  File='f1G.dat';   Size=1073741824;  Block=65536; Write=30;  Label='1GB / 70R30W   / 64K' }
  @{ Id='1G-RR-4K';    File='f1G.dat';   Size=1073741824;  Block=4096;  Write=0;   Label='1GB / RandRead  / 4K  (IOPS)' }
  @{ Id='1G-RW-4K';    File='f1G.dat';   Size=1073741824;  Block=4096;  Write=100; Label='1GB / RandWrite / 4K  (IOPS)' }
)

$results = @()
foreach ($t in $tests) {
    $path = Join-Path $testDir $t.File
    $dsArgs = @("-c$($t.Size)", "-b$($t.Block)", '-d30', '-W5', '-t4', '-o8', '-r', "-w$($t.Write)", '-L', '-Sh', $path)
    Write-Host "[$(Get-Date -Format HH:mm:ss)] Running $($t.Id): diskspd $($dsArgs -join ' ')"
    $out = & $exe @dsArgs 2>&1 | Out-String

    $totalLine = ($out -split "`n" | Select-String -Pattern '^\s*total:' | Select-Object -First 1).ToString().Trim()
    $parts = $totalLine -split '\s*\|\s*|\s{2,}' | Where-Object { $_ -ne '' -and $_ -ne 'total:' }

    $p95Read = ''; $p95Write = ''
    foreach ($line in ($out -split "`n")) {
        if ($line -match '^\s*95th\s+\|') {
            $pparts = $line.Trim() -split '\s*\|\s*'
            if ($pparts.Count -ge 3) { $p95Read = $pparts[1].Trim(); $p95Write = $pparts[2].Trim() }
        }
    }

    $bytes = ''; $ios = ''; $mibs = ''; $iops = ''; $avgLat = ''
    if ($parts.Count -ge 5) {
        $bytes = $parts[0]; $ios = $parts[1]; $mibs = $parts[2]; $iops = $parts[3]; $avgLat = $parts[4]
    }
    $results += [pscustomobject]@{
        Id=$t.Id; Label=$t.Label; Size=$t.Size; Block=$t.Block; WritePct=$t.Write
        Bytes=$bytes; IOs=$ios; MiBps=$mibs; IOPS=$iops; AvgLat_ms=$avgLat
        P95Read_ms=$p95Read; P95Write_ms=$p95Write
    }
}

$jsonOut = $results | ConvertTo-Json -Depth 4 -Compress
Write-Output '=== RESULTS (JSON) ==='
Write-Output $jsonOut
Write-Output ''
Write-Output '=== RESULTS (TABLE) ==='
$results | Format-Table Id,Label,MiBps,IOPS,AvgLat_ms,P95Read_ms,P95Write_ms -AutoSize | Out-String | Write-Output

if ($ResultFile) {
    $jsonOut | Out-File -FilePath $ResultFile -Encoding utf8 -Force
    Write-Output "Saved: $ResultFile"
}

# Cleanup
Remove-Item "$testDir\*" -Force -ErrorAction SilentlyContinue
Remove-Item $testDir -Force -ErrorAction SilentlyContinue
Get-SmbGlobalMapping -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPath -eq $DriveLetter } |
  Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue

Write-Output 'DONE'
