param(
    [Parameter(Mandatory=$true)][string]$StorageAccount,
    [Parameter(Mandatory=$true)][string]$ShareName,
    [Parameter(Mandatory=$true)][string]$AccountKey,
    [string]$DriveLetter = 'T:',
    [string]$DiskSpd     = 'C:\Tools\diskspd\diskspd.exe',
    [int]$DurationSec    = 30
)
$ErrorActionPreference = 'Continue'
if (-not (Test-Path $DiskSpd)) { throw "diskspd not found at $DiskSpd" }

$remote = "\\$StorageAccount.file.core.chinacloudapi.cn\$ShareName"
$user   = "localhost\$StorageAccount"
Get-SmbGlobalMapping -ErrorAction SilentlyContinue | Where-Object { $_.LocalPath -eq $DriveLetter } | Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue
$sec  = ConvertTo-SecureString $AccountKey -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential($user, $sec)
New-SmbGlobalMapping -RemotePath $remote -Credential $cred -LocalPath $DriveLetter -Persistent:$false -ErrorAction Stop | Out-Null
Start-Sleep 2

$testDir  = "$DriveLetter\bench4k"
$testFile = "$testDir\test.dat"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
& $DiskSpd -c1G -t1 -o1 -d1 -w100 -Sh $testFile | Out-Null

$workloads = @(
    @{ Label='4K-RR-HighQD';   Args=@('-b4K','-t4','-o8','-r','-w0',  "-d$DurationSec",'-W3','-L','-Sh') },
    @{ Label='4K-RW-HighQD';   Args=@('-b4K','-t4','-o8','-r','-w100',"-d$DurationSec",'-W3','-L','-Sh') },
    @{ Label='4K-MIX-HighQD';  Args=@('-b4K','-t4','-o8','-r','-w30', "-d$DurationSec",'-W3','-L','-Sh') },
    @{ Label='4K-RR-LowQD';    Args=@('-b4K','-t1','-o1','-r','-w0',  "-d$DurationSec",'-W3','-L','-Sh') },
    @{ Label='4K-RW-LowQD';    Args=@('-b4K','-t1','-o1','-r','-w100',"-d$DurationSec",'-W3','-L','-Sh') }
)

$results = @()
foreach ($w in $workloads) {
    Write-Host "=== $($w.Label) ==="
    $argList = @($w.Args) + @($testFile)
    $out = & $DiskSpd @argList 2>&1 | Out-String
    $iops=$null; $mib=$null; $avg=$null; $p95=$null; $p99=$null
    if ($out -match 'total:\s+\d[\d,]*\s+\|\s+\d[\d,]*\s+\|\s+([\d\.]+)\s+\|\s+([\d\.]+)\s+\|\s+([\d\.]+)') {
        $mib=[double]$matches[1]; $iops=[double]$matches[2]; $avg=[double]$matches[3]
    }
    foreach ($l in ($out -split "`r?`n")) {
        if ($l -match '^\s*95th\s*\|\s*[\d\.]+\s*\|\s*[\d\.]+\s*\|\s*([\d\.]+)') { $p95=[double]$matches[1] }
        if ($l -match '^\s*99th\s*\|\s*[\d\.]+\s*\|\s*[\d\.]+\s*\|\s*([\d\.]+)') { $p99=[double]$matches[1] }
    }
    $results += [pscustomobject]@{ Label=$w.Label; IOPS=$iops; MiBps=$mib; AvgMs=$avg; P95Ms=$p95; P99Ms=$p99 }
}

$results | Format-Table -AutoSize
$out = 'C:\Tools\benchmark\4k-bench-result.json'
New-Item -ItemType Directory -Path (Split-Path $out) -Force | Out-Null
$results | ConvertTo-Json | Set-Content -Path $out -Encoding UTF8
Write-Host "Saved: $out"

Remove-Item $testFile -Force -ErrorAction SilentlyContinue
Get-SmbGlobalMapping -ErrorAction SilentlyContinue | Where-Object { $_.LocalPath -eq $DriveLetter } | Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue
