# apply.ps1 — 把中文系统编码补丁应用到 bbport 的 scripts 目录
# 用法：  powershell -ExecutionPolicy Bypass -File .\apply.ps1 -PortDir "D:\path\to\bbport-windows"
param([Parameter(Mandatory=$true)][string]$PortDir)
$dst = Join-Path $PortDir 'scripts'
if (-not (Test-Path $dst)) { Write-Error "找不到 $dst —— 请把 -PortDir 指向含 Bloodborne.exe 的 bbport-windows 目录"; exit 1 }
# 先备份原始脚本
$bak = Join-Path $PortDir 'scripts.orig-backup'
if (-not (Test-Path $bak)) { Copy-Item $dst $bak -Recurse -Force; Write-Host "已备份原始脚本到 $bak" }
Copy-Item (Join-Path $PSScriptRoot 'scripts-patched\*.py') $dst -Force
Write-Host "✅ 编码补丁已应用到 $dst （6 个文件）"
