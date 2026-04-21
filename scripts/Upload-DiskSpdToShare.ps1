<#
.SYNOPSIS
  将 DiskSpd.exe 预先上传到 Azure Files 共享的 tools/ 目录，
  供 Session Host 在无互联网/受限网络场景中离线获取。

.EXAMPLE
  .\Upload-DiskSpdToShare.ps1 -StorageAccount stavdhaieru6h01 -ShareName share1tb -AccountKey 'xxxxx=='
#>
param(
  [Parameter(Mandatory=$true)][string]$StorageAccount,
  [Parameter(Mandatory=$true)][string]$ShareName,
  [Parameter(Mandatory=$true)][string]$AccountKey
)
$ErrorActionPreference = 'Stop'

$tmp = Join-Path $env:TEMP 'diskspd-up'
$zip = Join-Path $tmp 'DiskSpd.zip'
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri 'https://github.com/microsoft/diskspd/releases/download/v2.2/DiskSpd.zip' `
                  -OutFile $zip -UseBasicParsing -TimeoutSec 120
Expand-Archive -Path $zip -DestinationPath "$tmp\unz" -Force
$exe = "$tmp\unz\amd64\diskspd.exe"

# Map share via SMB global mapping, copy into tools/, unmap
$letter = 'Z:'
$remote = "\\$StorageAccount.file.core.chinacloudapi.cn\$ShareName"
Get-SmbGlobalMapping -ErrorAction SilentlyContinue | Where-Object { $_.LocalPath -eq $letter } |
  Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue
$sec  = ConvertTo-SecureString $AccountKey -AsPlainText -Force
$cred = [System.Management.Automation.PSCredential]::new("localhost\$StorageAccount", $sec)
New-SmbGlobalMapping -LocalPath $letter -RemotePath $remote -Credential $cred `
  -Persistent $false -RequirePrivacy $true `
  -FullAccess @('NT AUTHORITY\SYSTEM','BUILTIN\Administrators') -ErrorAction Stop | Out-Null

New-Item -ItemType Directory -Path "$letter\tools" -Force | Out-Null
Copy-Item $exe "$letter\tools\diskspd.exe" -Force
Get-ChildItem "$letter\tools" | Select-Object Name,Length

Get-SmbGlobalMapping -ErrorAction SilentlyContinue | Where-Object { $_.LocalPath -eq $letter } |
  Remove-SmbGlobalMapping -Force -ErrorAction SilentlyContinue

Remove-Item $tmp -Recurse -Force
Write-Output 'DONE: diskspd.exe uploaded to tools/diskspd.exe'
